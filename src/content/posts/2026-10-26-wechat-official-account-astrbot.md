---
title: 给 AstrBot 接微信公众号：一路踩到的坑
published: 2026-10-26
description: 从域名校验、虚假的 200002、管理员扫码，到引用组件被丢弃、纯文本 future 不 resolve；最后为什么连这个渠道一起放弃了。
tags: [astrbot, wechat, python, caddy]
category: 踩坑
---

想把公众号接进自建的 AstrBot，动机很简单：接进去之后，读者在公众号里就能问校历、查空教室，不用再维护一套后台自动回复。

结果一路踩坑，最后**渠道弃用了**。但踩到的坑本身挺有价值，尤其是其中两个属于 AstrBot 的通用缺陷，跟公众号无关。

## 先认清一个前提：后台自动回复会失效

微信官方文档写得很直接：

> 启用后，用户发送的消息将转发至该地址，**网站中设置的自动回复和自定义菜单将失效**。

也就是说，一旦填了服务器地址，后台那套「关键词回复 / 被关注回复 / 收到消息回复」全部作废，菜单点击事件也改推给开发者服务器。想保留这些体验，只能自己在服务端重建。

## 入口已经搬走了

老的 `mp.weixin.qq.com → 设置与开发 → 开发接口管理` 自 2025-12-01 起迁到**微信开发者平台**，老后台只留一条迁移通知。

```
微信开发者平台 → 我的业务 → 公众号 → 基础信息 → 域名与消息推送配置
                                      └─ 开发密钥（AppID / AppSecret / IP 白名单）
```

注意登录人必须是**管理员或开发者**——运营者在平台上连账号信息都看不到，这一点只写在迁移文档的补充说明里，界面上没有任何提示。

## 坑一：两套域名校验文件

微信有两套独立的校验机制，文件不能互相替代：

| 用途 | 文件名 | 内容 |
|---|---|---|
| JS 接口安全域名 | `MP_verify_<16位>.txt` | 那 16 位串 |
| 开发者平台安全检测 | `<32位hex>.txt` | 40 位 hex 字符串 |

两个都要放在域名根路径下，**80 和 443 都要能直接返回 200**。只在 443 上放、靠 301/308 把 80 跳过去是常见的失败姿势——微信的校验请求不保证跟随重定向。

Caddy 里直接 `respond` 就行，让它走静态文件反而容易因为路径配置出错：

```caddyfile
handle /MP_verify_xxxxxxxxxxxxxxxx.txt {
    respond "xxxxxxxxxxxxxxxx" 200
}
```

## 坑二：`200002 invalid args` 是个万能垃圾桶

保存消息推送配置时报这个错，`errmsg` 只有四个字，不告诉你哪个字段错。我逐个排了四类原因：

1. **域名校验没做** —— 先做，`type=check_domain&step=1` 那一步返回 `ret:0 ok` 才算过
2. **参数不合规** —— `EncodingAESKey` 必须 43 位，`Token` 3~32 位。换成平台自带「随机生成」的值仍然报错，就说明不是值的问题
3. **保存时弹安全二维码** —— 要求管理员扫码并确认，轮询接口里 `data.operator_name` 为空就说明这次确认微信没认
4. **URL 被判成「违规链接」** —— 这次的真正原因

第四条最难猜：微信对配置的回调地址做安全检测，抓取到的内容是 `err` 这种极短非 HTML 文本，很容易被判成异常页面。它之后会给你一个「提交证明材料」的申诉入口，违规链接通常就是回调地址本身。

**申诉通过之后，同样的 URL / Token / AESKey 一次就存上了，一个字都不用改。** 所以遇到这个错误码，先去申诉页看看有没有待处理的链接，比逐项改参数快得多。

## 坑三：引用回复会把整条消息吃掉

配置终于保存成功、消息也进来了，但用户发关键词后收到的却是「正在思考…」，必须再发一条才拿到内容。

查日志发现：

```
Prepare to send - [引用消息] 空教室查询：https://...
[WARN] 还没实现这个消息类型的发送逻辑: ComponentType.Reply
```

AstrBot 的全局配置里 `reply_with_quote` 是给 QQ 群用的，回复会被包成「引用消息」组件。而公众号适配器只实现了 `Plain` / `Image` / `Voice` 三种组件的发送，遇到 `Reply` 就打一条 WARN 然后**整条消息不发出**。

`segmented_reply`（分段回复）同理：拆成多条，而被动回复一次只能返回一条 XML，后面的段落直接丢。

处理办法是在**公众号自己那份 profile** 里关掉，别动全局：

```python
ps["reply_with_quote"] = False
ps["reply_with_mention"] = False
ps["segmented_reply"]["enable"] = False
```

## 坑四：纯文本被动回复不 resolve future（上游 bug）

关掉引用之后 `Prepare to send` 干净了，但仍然超时。这次翻适配器源码，找到的是个正经 bug：

```python
if isinstance(comp, Plain):
    ...
    else:  # 被动回复模式
        self.message_out["cached_xml"] = plain_chunks
        logger.debug("... Message not sent.")
        # ← 没有 set_result(future)
```

而适配器的回调在等这个 future：

```python
result = await asyncio.wait_for(asyncio.shield(future), 180)
```

`handle_callback()` 又只在回调任务完成后、4 秒窗口内才去读 `cached_xml`。future 永远悬着 → 任务永远不完成 → 窗口必然超时 → 只能返回占位符。

讽刺的是 `Image` 和 `Voice` 分支都有 `set_result`，**只有最常用的纯文本漏了**。而且它不报错，表现只是「先回一句正在思考」，很容易被当成模型慢。

修法三行，顺手把同分支的两个相邻问题一起处理了：

```python
# 1) 累加而不是覆盖，多段 Plain 不会只剩最后一段
self.message_out.setdefault("cached_xml", [])
self.message_out["cached_xml"].extend(plain_chunks)

# 2) send() 末尾统一 resolve，等所有组件收集完
if not active_send_mode:
    future = cast(dict, message_obj.raw_message).get("future")
    if isinstance(future, asyncio.Future) and not future.done():
        future.set_result(None)
```

这个改动提到上游了（[PR #10776](https://github.com/AstrBotDevs/AstrBot/pull/10776)）。它对所有公众号用户都有用，跟具体接什么机器人无关。

## 坑五：兜底开关会静默接管所有消息

客户端关键词插件里我做了个「兜底回复」开关，本意是「AI 答不了时给条引导」。实际行为是：**任何没命中关键词的消息都回这句固定文案，并 `stop_event()`**——模型连碰都碰不到。

于是发一句「哈喽」，收到的是「这个问题我暂时无法回复 + 欢迎语」。看起来像模型不干活，其实是它被拦在门外了。

公众号的被动回复只有一条，插件的兜底和模型的回答**天然互斥**，没有办法「先让 AI 试、失败了再补一句」。所以正确做法是把「答不了怎么引导」写进人格 prompt，而不是做成一个兜底开关。

## 最后为什么还是弃用

链路全通了，关键词秒回，模型也能回。但真正的问题是延迟分布：

```
12:00:00.249  「你是谁」收到
12:00:10.928  回复生成完成        → 10.7 秒
12:00:48.940  「#new」指令
12:00:48.968  回复发出            → 0.028 秒
```

内置指令 28 毫秒，走模型 10.7 秒。而微信被动回复的窗口是 **5 秒硬断连**，AstrBot 留余量只用 4 秒。也就是说：任何超过 4 秒的回复，用户都要经历「收到占位符 → 再发一条 → 拿到答案」。

对比 QQ 群：同样的模型、同样的 10 秒，用户只是多等几秒，没有二次触发。**同一个后端，两个渠道的体验完全不是一个量级。**

再叠加账号本身的限制（未认证号所有业务接口 `48001`）：

- 不能主动推送（客服消息接口不可用）
- 不能发图片（需要 `media_id`，素材接口不可用）
- 不能用菜单接口，后台菜单又被服务器配置接管

所以这个渠道能跑通，但产品形态是残的。

## 顺手确认的两件事

**事件拿不到**：`subscribe`（被关注）、`CLICK`（菜单点击）这类事件，在适配器 `convert_message` 里被一个 `else` 直接丢弃：

```python
else:
    logger.warning(f"暂未实现的事件: {msg.type}")
    return
```

wechatpy 其实已经把这些解析成 `SubscribeEvent` / `ClickEvent` 了，只是没往上抛。要做「被关注自动回复」必须改内核。好消息是地基现成：`MessageType.OTHER_MESSAGE` 与 `EventMessageType.OTHER_MESSAGE` 都已存在，aiocqhttp / line / kook / misskey 四个适配器已经在用它处理事件，照抄即可。

**菜单能做但要认证**：接口路径是有的（`cgi-bin/menu/create` 等），未认证号 `48001`，认证后由插件调用即可，不需要改内核——但点击事件还是得靠上面那条。

## 留下的东西

渠道撤了，技术资产留着：

- 一个关键词自动回复插件（精确/包含/正则三种匹配、首条欢迎语、WebUI 管理页），已经开源
- 一个上游 PR，修掉纯文本被动回复的 future 问题
- 一套「让出站请求走固定 IP」的反向代理方案：自签 CA + 非标端口 + 把 CA 注入容器信任库，用于绕开 IP 白名单被动态 IP 折腾的问题

如果哪天真的需要公众号，前提是先给账号认证；未认证号加被动回复 5 秒窗口，这个组合在产品上基本没有解。
