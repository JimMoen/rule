## // substore 文件内填入以下远程脚本：

```
https://gh-proxy.com/https://raw.githubusercontent.com/xream/scripts/main/surge/modules/sub-store-scripts/sing-box/template.js#type=组合订阅&name=singbox&outbound=🕳ℹ️手动选择|自动选择🏷ℹ️^(?!.*(?:官网|剩余|流量|套餐|免费|订阅|到期时间|直连|[0-9]GB|Expire Date|Traffic|ExpireDate)).*🕳ℹ️香港手动|香港自动🏷ℹ️^(?!.*(?:ZJ|zijian|自建)).*(🇭🇰|HK|hk|香港|港|HongKong)🕳ℹ️日本手动|日本自动🏷ℹ️^(?!.*(?:ZJ|zijian|自建)).*(🇯🇵|JP|jp|日本|日|Japan)🕳ℹ️狮城手动|狮城自动🏷ℹ️^(?!.*(?:ZJ|zijian|自建)).*(新加坡|坡|狮城|SG|Singapore)🕳ℹ️美国手动|美国自动🏷ℹ️^(?!.*(?:ZJ|zijian|自建|AUS|RUS)).*(🇺🇸|US|美国|美|United States)
```

地区自动组使用 `urltest`，每 10 分钟测试一次，`tolerance` 为 50 ms。只有新节点
比当前节点快至少 50 ms 时才会切换，以减少频繁变动。`urltest` 只测延迟，不测
带宽，sing-box 当前没有按带宽自动选择的 outbound。
