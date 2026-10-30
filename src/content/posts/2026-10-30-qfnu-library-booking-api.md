---
title: 曲阜师范大学图书馆预约系统 API 逆向文档
published: 2026-10-30
description: 从 IDS + CAS 登录、AES 加密参数到预约、签到、签退接口，一份可以照着直接写客户端的逆向笔记。
tags: [api, reverse-engineering, qfnu, http]
category: 逆向
---

> 本文档通过逆向分析曲阜师范大学图书馆预约系统得出，供第三方开发者参考，用于开发基于图书馆预约系统的辅助工具。**请注意：所有接口均为 HTTP 协议（非 HTTPS）。**

---

## 目录

1. [域名与基础设施](#1-域名与基础设施)
2. [认证流程（IDS + CAS）](#2-认证流程ids--cas)
3. [通用请求头](#3-通用请求头)
4. [AES 加密方案汇总](#4-aes-加密方案汇总)
5. [API 接口清单](#5-api-接口清单)
   - [5.1 获取校区/楼宇/区域](#51-获取校区楼宇区域)
   - [5.2 获取时间段](#52-获取时间段)
   - [5.3 获取座位列表](#53-获取座位列表)
   - [5.4 预约座位](#54-预约座位)
   - [5.5 取消预约](#55-取消预约)
   - [5.6 查询预约列表](#56-查询预约列表)
   - [5.7 签到](#57-签到)
   - [5.8 查询当前座位](#58-查询当前座位)
   - [5.9 签退](#59-签退)
6. [响应码约定](#6-响应码约定)
7. [预约错误消息速查表](#7-预约错误消息速查表)
8. [安全与风控注意事项](#8-安全与风控注意事项)

---

## 1. 域名与基础设施

| 系统 | 域名 |
|------|------|
| IDS 统一认证 | `http://ids.qfnu.edu.cn` |
| 图书馆业务 | `http://libyy.qfnu.edu.cn` |

所有接口均基于 **HTTP**（非 HTTPS），`Content-Type` 以 `application/json` 和 `application/x-www-form-urlencoded` 为主。

---

## 2. 认证流程（IDS + CAS）

图书馆业务接口需要携带 `Bearer Token`。获取 Token 的完整链路为 **5 步 IDS 登录 + 1 个可选滑块验证**：

```
Step 1:  GET  IDS 登录页          → 提取 salt + execution
Step 1.5: GET/POST  滑块验证码    → 获取/提交滑块（IDS 按需开启）
Step 2:  POST IDS 登录表单        → 302 跳转至 CAS 回调
Step 3:  GET  跟随跳转            → 302 跳转至 /api/cas/cas
Step 4:  GET  /api/cas/cas        → 从 Location 末尾 32 字符提取 CAS Token
Step 5:  POST /api/cas/user       → 用 CAS Token 换取 Bearer Token
```

### Step 1: 获取 IDS 登录页

| 项目 | 内容 |
|------|------|
| **方法** | `GET` |
| **URL** | `http://ids.qfnu.edu.cn/authserver/login?service=http%3A%2F%2Flibyy.qfnu.edu.cn%2Fapi%2Fcas%2Fcas` |
| **请求头** | `User-Agent: <浏览器 UA>`，`Referer: http://libyy.qfnu.edu.cn/` |
| **响应** | HTML 页面 |

从 HTML 中正则提取两个参数：
- `id="pwdEncryptSalt" value="..."` → **salt**（用于密码加密的 AES 密钥）
- `name="execution" value="..."` → **execution**（登录表单必需参数）

### Step 1.5: 滑块验证码（按需触发）

并非每次登录都要求滑块验证，需探测式处理。

#### 1.5a 获取滑块图片

| 项目 | 内容 |
|------|------|
| **方法** | `GET` |
| **URL** | `http://ids.qfnu.edu.cn/authserver/common/openSliderCaptcha.htl` |
| **请求头** | `User-Agent: <浏览器 UA>`，`Referer: http://ids.qfnu.edu.cn/authserver/login?service=...` |

**成功响应：**
```json
{
  "bigImage": "<base64 编码的缺口背景图>",
  "smallImage": "<base64 编码的滑块小块图>"
}
```

- 若 `bigImage` / `smallImage` 为空，或响应体不是合法 JSON → IDS 未开启滑块验证，跳过此步。
- `smallImage` 末 16 字节用作后续滑块加密的 AES 密钥。

#### 1.5b 提交滑块验证

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://ids.qfnu.edu.cn/authserver/common/verifySliderCaptcha.htl` |
| **Content-Type** | `application/x-www-form-urlencoded` |
| **请求头** | `Referer: http://ids.qfnu.edu.cn/authserver/login?service=...`，`Origin: http://ids.qfnu.edu.cn` |

**请求体：** `sign=<AES加密后的轨迹数据>`（form-urlencoded）

**轨迹数据明文 JSON：**
```json
{
  "canvasLength": 280,
  "moveLength": <移动距离（px）>,
  "tracks": [
    {"a": <累计x位移>, "b": <累计y偏移>, "c": <时间间隔(ms)>},
    ...
  ]
}
```

- 加密方案：AES-128-CBC，Key = `smallImage` 末 16 字节，IV = 随机 16 字符，64 字符随机前缀 + JSON，PKCS7 填充。
- 缺口识别思路：灰度化 → 5×5 模糊 → Sobel X 边缘检测 → Y 轴 30%-70% 区域列梯度求和 → 最大梯度列为缺口位置。
- 轨迹生成思路：25-40 步 6 阶段模拟（暂停→低速→中速→高速→低速→暂停），带随机 Y 轴抖动。

**成功响应：** `{"errorCode": 1}`

建议每次失败后重新获取验证码图片再试，最多重试 10 次（间隔 3 秒）。

### Step 2: 提交 IDS 登录

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://ids.qfnu.edu.cn/authserver/login?service=http%3A%2F%2Flibyy.qfnu.edu.cn%2Fapi%2Fcas%2Fcas` |
| **Content-Type** | `application/x-www-form-urlencoded` |

**请求体（form 字段）：**

| 字段 | 值 | 说明 |
|------|-----|------|
| `username` | 学号 | 明文 |
| `password` | AES 密文 | 加密方案见下方 |
| `captcha` | `""` | 留空 |
| `_eventId` | `submit` | 固定值 |
| `cllt` | `userNameLogin` | 固定值 |
| `dllt` | `generalLogin` | 固定值 |
| `lt` | `""` | 留空 |
| `execution` | Step 1 提取的值 | |

**密码加密方案（AES-128-CBC）：**
- Key = Step 1 提取的 `salt`
- IV = 随机 16 字符
- 明文 = 64 字符随机前缀 + 原始密码
- PKCS7 填充 → Base64 编码

**成功响应：** `HTTP 302`，`Location` 头指向图书馆 CAS 回调地址。

### Step 3-4: CAS 重定向

| Step | 方法 | URL | 说明 |
|------|------|-----|------|
| 3 | `GET` | Step 2 的 `Location` | 跟随 IDS 跳转到图书馆 |
| 4 | `GET` | `http://libyy.qfnu.edu.cn/api/cas/cas` | 核心 CAS 接口 |

Step 4 返回 `HTTP 302`，从响应的 `Location` 头**末尾 32 个字符**提取 CAS Token。

### Step 5: 换取 Bearer Token

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/cas/user` |
| **Content-Type** | `application/json` |

**请求体：**
```json
{"cas": "<32位CAS Token>"}
```

**成功响应：**
```json
{
  "code": 1,
  "member": {
    "name": "用户名",
    "token": "<Bearer Token>"
  },
  "msg": "..."
}
```

- 返回的 `member.token` 即为后续所有业务接口使用的 Bearer Token。
- 实测 Token 有效期约 **90-100 分钟**。
- 整个认证到业务请求链路必须共用同一个 HTTP Cookie Jar（重定向不自动跟随，需手动提取 Location）。

---

## 3. 通用请求头

图书馆业务接口（Step 5 之后）统一携带以下请求头：

```
Content-Type: application/json
Connection: keep-alive
Accept: application/json, text/plain, */*
lang: zh
X-Requested-With: XMLHttpRequest
User-Agent: <浏览器UA>
Origin: http://libyy.qfnu.edu.cn
Referer: http://libyy.qfnu.edu.cn/h5/index.html
Authorization: bearer<Token>
```

> ⚠️ **注意：** `Authorization` 头格式为 `"bearer" + Token`，**bearer 与 Token 之间没有空格**。这与标准 OAuth 2.0 的 `Bearer <token>` 格式不同，是此系统特有的格式。

---

## 4. AES 加密方案汇总

系统中存在 3 种 AES-128-CBC 加密场景：

| 用途 | Key | IV | 明文格式 | 填充 |
|------|-----|-----|---------|------|
| IDS 密码加密 | `salt`（登录页提取） | 随机 16 字符 | 64 字符随机前缀 + 密码 | PKCS7 |
| 滑块 sign 加密 | `smallImage` 末 16 字节 | 随机 16 字符 | 64 字符随机前缀 + 轨迹 JSON | PKCS7 |
| 预约/签到数据加密 | `YYYYMMDD + reverse(YYYYMMDD)`（共 16 字节，如日期 `20260705` 时 Key = `2026070550706020`） | `ZZWBKJ_ZHIHUAWEI`（固定） | 纯 JSON | PKCS7 |

---

## 5. API 接口清单

### 5.1 获取校区/楼宇/区域

获取三级层级结构（校区 → 楼层 → 区域）及可用日期列表。

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/reserve/index/quickSelect` |
| **鉴权** | **不需要**（`authorization` 可传空字符串） |

**请求体：**
```json
{
  "id": "1",
  "date": "2026-07-05",
  "categoryIds": ["1"],
  "members": 0,
  "authorization": ""
}
```

**成功响应（code 为字符串 `"0"`，注意与其他接口不同）：**
```json
{
  "code": "0",
  "data": {
    "date": ["2026-07-05", "2026-07-06"],
    "premises": [
      {
        "id": "1",
        "name": "曲阜校区",
        "nameMerge": "",
        "parentId": "0",
        "topId": "1",
        "total_num": 1200,
        "free_num": 586
      }
    ],
    "storey": [
      {
        "id": "10",
        "name": "2F",
        "nameMerge": "",
        "parentId": "1",
        "topId": "10",
        "total_num": 300,
        "free_num": 150
      }
    ],
    "area": [
      {
        "id": "100",
        "name": "东区阅览室",
        "nameMerge": "",
        "parentId": "10",
        "topId": "100",
        "total_num": 56,
        "free_num": 23
      }
    ]
  },
  "msg": "..."
}
```

**字段说明：**
- `premises`：校区级
- `storey`：楼层级（通过 `parentId` 关联到 `premises[].id`）
- `area`：区域级（通过 `parentId` 关联到 `storey[].id`），**预约时使用的 roomID 即 area 的 `id`**
- `total_num` / `free_num`：可能是字符串也可能是数字，需兼容解析

---

### 5.2 获取时间段

根据 area ID 获取对应日期可预约的时间段。

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Seat/date` |
| **鉴权** | 需要 Bearer Token |

**请求体：**
```json
{"build_id": 100}
```

**成功响应：**
```json
{
  "code": 1,
  "data": [
    {
      "day": "2026-07-05",
      "times": [
        {"id": 123456},
        {"id": 123457}
      ]
    }
  ],
  "msg": "..."
}
```

- 匹配 `day == 目标日期` 的条目，取第一个 `times[0].id` 作为时间段 ID（segment）。
- `id` 字段可能是字符串或数字。

---

### 5.3 获取座位列表

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Seat/seat` |
| **鉴权** | 通常需要 Bearer Token（但部分查询场景可不校验） |

**请求体：**
```json
{
  "area": 100,
  "segment": 123456,
  "day": "2026-07-05",
  "startTime": "08:00",
  "endTime": "22:00"
}
```

**成功响应：**
```json
{
  "code": 1,
  "data": [
    {
      "id": "13855",
      "no": "071",
      "name": "71号",
      "status_name": "空闲",
      "status": "1"
    },
    {
      "id": "13856",
      "no": "072",
      "name": "72号",
      "status_name": "已预约",
      "status": "2"
    }
  ],
  "msg": "..."
}
```

**座位状态码对照：**

| `status` | `status_name` | 含义 |
|----------|---------------|------|
| `"1"` | 空闲 | 可预约 |
| `"2"` | 已预约 | 已被占用 |
| `"3"` | 锁定 | 暂时不可用 |
| `"6"` | 使用中 | 正在被使用 |

---

### 5.4 预约座位

**最核心的接口。**

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Seat/confirm` |
| **鉴权** | 需要 Bearer Token（注意 `Authorization: bearer<Token>` 无空格） |

**请求体：**
```json
{"aesjson": "<AES加密后的预约数据>"}
```

**加密前明文 JSON：**
```json
{"seat_id": "13855", "segment": "123456"}
```

- 加密方案：AES-128-CBC，Key = `当天日期(YYYYMMDD) + 反转后的当天日期`，IV = `ZZWBKJ_ZHIHUAWEI`，PKCS7 填充后 Base64 编码。
- 将加密结果填入 `aesjson` 字段。

**成功响应：**
```json
{
  "code": 0,
  "msg": "预约成功",
  "data": {"id": "2599221"}
}
```

**`data` 字段兼容性：** 可能是对象 `{"id":"..."}`、字符串 `"..."` 或数字，需全部兼容。

**所有可能的响应情况及处理建议：**

| 响应特征 | 含义 | 处理建议 |
|---------|------|---------|
| `code:0, msg:"预约成功"` | 预约成功 | 提取 `data` 中的预约 ID |
| `code:0, msg:"当前用户在该时段已存在座位预约，不可重复预约"` | 已预约 | 视为成功，标记已预约状态 |
| `code:0, msg:null` | **开放临界态**（放号瞬间过渡状态） | 短暂重试（秒级），超时后判定失败 |
| `code:0, msg:"该空间当前状态不可预约"` | 该座位已被占用/不可用 | 换下一个候选座位 |
| `code:0, msg:"申请人已被列入此系统黑名单，不能预约!"` | 黑名单 | **立即终止全部重试**，通知用户 |
| `code:-7, msg:...` | **限流** | 立即终止，5 分钟后重试 |
| `code:10001, msg:"其他设备登录"` | 登录态被踢下线 | 重新登录后重试 |
| `msg 含"开放预约时间"` | 还未到预约开放时间 | 等待至开放时间 |
| `msg 含"尚未登录"` | Token 过期 | 重新登录后重试 |

---

### 5.5 取消预约

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Space/cancel` |

**请求体：**
```json
{
  "id": "2599221",
  "authorization": "bearer<Token>"
}
```

**成功响应：** `{"code": 1, "msg": "..."}`
**失败：** `code != 1`

> Token 需同时出现在 Header `Authorization` 和请求体 `authorization` 中。

---

### 5.6 查询预约列表

查询当前用户的所有预约记录。

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/index/subscribe` |

**请求体：**
```json
{"authorization": "bearer<Token>"}
```

**成功响应：**
```json
{
  "code": 1,
  "data": [
    {
      "id": "2599221",
      "areaName": "东区阅览室",
      "spaceName": "71号",
      "no": "071",
      "statusName": "已预约",
      "cancel": 0
    }
  ],
  "msg": "..."
}
```

- `cancel`：`0` = 可取消，`1` = 不可取消。

---

### 5.7 签到

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Seat/touch_qr_books` |

**请求体：**
```json
{
  "aesjson": "<AES加密后的签到数据>",
  "authorization": "bearer<Token>"
}
```

**加密前明文：** `{"method":"checkin"}`
- 加密方案与预约一致（日期 Key + 固定 IV）。

**成功响应：** `{"code": 1, "msg": "..."}`
**已签到（仍视为成功）：** 响应体含 `"不用重复签到"` 字样

---

### 5.8 查询当前座位

签退前查询当前用户正在使用或已预约的座位。

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Member/seat` |

**请求体：**
```json
{
  "page": 1,
  "limit": 3,
  "authorization": "bearer<Token>"
}
```

**成功响应：**
```json
{
  "code": 1,
  "data": {
    "data": [
      {
        "id": "13855",
        "area": "东区阅览室",
        "no": "071",
        "statusName": "使用中"
      }
    ]
  },
  "msg": "..."
}
```

- 签退时应优先查找 `statusName` 含 `"使用中"` 的座位。
- 若没有 `"使用中"` 状态的座位，则无需签退。

---

### 5.9 签退

| 项目 | 内容 |
|------|------|
| **方法** | `POST` |
| **URL** | `http://libyy.qfnu.edu.cn/api/Space/checkout` |

**请求体：**
```json
{
  "id": "<座位ID，来自 Member/seat 接口>",
  "authorization": "bearer<Token>"
}
```

**成功条件（满足任一即成功）：**
- `code == 1`
- `msg` 包含 `"完全离开操作成功"`
- `msg` 包含 `"已经签退"`

---

## 6. 响应码约定

| 接口 | 成功码 | 备注 |
|------|--------|------|
| QuickSelect | `"0"`（字符串） | 与其他接口语义相反 |
| CAS /user | `1` | |
| Seat/date | `1` | |
| Seat/seat | `1` | |
| Seat/confirm | `0` | 预约成功 |
| **Seat/confirm** | **`-7`** | 访问频繁（限流） |
| **Seat/confirm** | **`10001`** | 其他设备登录导致被踢下线 |
| Space/cancel | `1` | |
| index/subscribe | `1` | |
| Seat/touch_qr_books | `1` | |
| Member/seat | `1` | |
| Space/checkout | `1` | |

---

## 7. 预约错误消息速查表

| 消息关键词 | 类型 | 处理方式 |
|-----------|------|---------|
| `"预约成功"` | ✅ 成功 | 提取预约 ID |
| `"不可重复预约"` | ✅ 已预约 | 视为成功 |
| `msg:null`（code=0） | ⚠️ 临界态 | 短暂重试后判定 |
| `"该空间当前状态不可预约"` | ❌ 座位级失败 | 换下一候选座位 |
| `"黑名单"` | 🚫 永久失败 | 立即终止，通知用户 |
| `code:-7` / `"访问频繁"` | 🚫 限流 | 立即终止，5 分钟后重试 |
| `"开放预约时间"` | ⏳ 未到时间 | 等待至开放 |
| `"尚未登录"` | 🔄 需重登录 | 重新登录 |
| `code:10001` / `"其他设备登录"` | 🔄 被踢下线 | 重新登录 |

---

## 8. 安全与风控注意事项

1. **User-Agent 轮换：** 建议随机选用主流浏览器最新版 UA（Chrome / Edge / Firefox / Safari），同一会话期间保持 UA 不变。
2. **Cookie Jar 保持：** 认证→业务请求全链路必须共用同一个 HTTP Cookie Jar，不要自动跟随重定向。
3. **Token 有效期：** Bearer Token 约 90-100 分钟，建议缓存不超过 90 分钟。
4. **限流（code=-7）：** 一旦触发立即停止所有后续请求。
5. **预约频率控制：** 不要对 `/api/Seat/confirm` 发起高频请求。
6. **授权头特殊格式：** `Authorization: bearer<Token>`（无空格），这是该系统特有的格式。
7. **密码传输：** 密码在传输中使用 AES 加密，不要在日志中明文记录。
8. **滑块验证探测：** IDS 按需开启滑块验证——先请求 `openSliderCaptcha`，若返回空则跳过。
9. **预约加密 Key 的日期依赖：** 预约/签到数据加密使用当天日期生成密钥，跨天亮时需留意密钥变更。

---

## 附录：接口地址速查表

| 接口 | 方法 | 完整 URL |
|------|------|----------|
| IDS 登录页 | GET | `http://ids.qfnu.edu.cn/authserver/login?service=http%3A%2F%2Flibyy.qfnu.edu.cn%2Fapi%2Fcas%2Fcas` |
| IDS 登录提交 | POST | `http://ids.qfnu.edu.cn/authserver/login?service=http%3A%2F%2Flibyy.qfnu.edu.cn%2Fapi%2Fcas%2Fcas` |
| 获取滑块验证码 | GET | `http://ids.qfnu.edu.cn/authserver/common/openSliderCaptcha.htl` |
| 提交滑块验证 | POST | `http://ids.qfnu.edu.cn/authserver/common/verifySliderCaptcha.htl` |
| CAS 回调 | GET | `http://libyy.qfnu.edu.cn/api/cas/cas` |
| 换取 Bearer Token | POST | `http://libyy.qfnu.edu.cn/api/cas/user` |
| 校区/楼层/区域查询 | POST | `http://libyy.qfnu.edu.cn/reserve/index/quickSelect` |
| 获取时间段 | POST | `http://libyy.qfnu.edu.cn/api/Seat/date` |
| 获取座位列表 | POST | `http://libyy.qfnu.edu.cn/api/Seat/seat` |
| 预约座位 | POST | `http://libyy.qfnu.edu.cn/api/Seat/confirm` |
| 取消预约 | POST | `http://libyy.qfnu.edu.cn/api/Space/cancel` |
| 查询预约列表 | POST | `http://libyy.qfnu.edu.cn/api/index/subscribe` |
| 签到 | POST | `http://libyy.qfnu.edu.cn/api/Seat/touch_qr_books` |
| 查询当前座位 | POST | `http://libyy.qfnu.edu.cn/api/Member/seat` |
| 签退 | POST | `http://libyy.qfnu.edu.cn/api/Space/checkout` |

---

*文档版本：v1.0 · 最后更新：2026-07-05*
