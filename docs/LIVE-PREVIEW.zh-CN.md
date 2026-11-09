# 边说边出草稿

说话时，草稿文字会实时出现；点停止后，和以前一样由电脑上的准确模型（Qwen3-ASR）重新识别整段，把准确结果打进输入框。

草稿有两种显示位置，在语音页**点顶部那行提示文字**切换（录音时不能切换）：

- **输入框（默认）**：草稿以带下划线的“临时文字”直接出现在光标处，像打拼音时那样；说完整段换成准确结果。
- **只在顶部这一行**：输入框不动，草稿只显示在键盘顶部的提示行（v0.4.19 轻量版的方式）。某个 App 对临时文字处理不好时用这个。

## 原理

- 手机录音时每约 0.35 秒把新录到的声音（16 位 PCM）发给服务，不再等停止后一次传完整段。
- 服务把这些小段拼好放在内存里，同时喂给一个专门“边听边出字”的小模型（流式 Paraformer 中英双语，sherpa-onnx 运行，CPU 即可，比实时快约 10 倍）。草稿随键盘的结果查询一起返回。
- 停止时，服务直接用已收到的音频交给准确模型识别，不用再上传整段；如果中途丢了某一段，手机会自动退回到以前的整段上传。
- 所有识别仍在你自己的电脑或 AWS 上完成，音频和文字只在内存中，不落盘。

不开草稿模型也能用新版：服务没装草稿模型时，手机照样边录边传（长录音结束时不用再等大上传），只是键盘不显示草稿。旧版服务不认识新接口，手机会自动用以前的整段上传。

## 电脑上启用

1. 在运行桥接的 Python 环境里安装草稿依赖：

   ```powershell
   pip install -r bridge/requirements-stream.txt
   ```

2. 下载草稿模型（约 1 GB 压缩包，只需要解压出其中 3 个文件，共约 240 MB）：
   <https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2>

   解压后的文件夹里必须有 `tokens.txt`、`encoder.int8.onnx`、`decoder.int8.onnx`。其余文件可以删掉。

3. 启动桥接时多加一个参数，指向这个文件夹：

   ```powershell
   python -B bridge/server.py --desktop "你的 CapsWriter-v3 目录" --host 192.168.1.20 --asr-port 6016 --token-file "配对码文件" --stream-model "D:\models\sherpa-onnx-streaming-paraformer-bilingual-zh-en"
   ```

   启动输出里出现 `Live preview: streaming draft text while recording.` 就说明草稿模型已加载。文件不全或没装依赖时，桥接会直接报错退出并说明原因。

## AWS 上启用

1. 更新代码后安装依赖：`sudo /srv/capswriter/venv-bridge/bin/pip install -r /srv/capswriter/app/bridge/requirements-stream.txt`
2. 把上面 3 个模型文件放到 `/srv/capswriter/private/stream-model/`，并 `chown -R capswriter:capswriter` 该目录。
3. 新版 `capswriter-gateway.service` 把网关内存上限从 512M 提到 1536M（草稿模型约占 350 MB）。重新安装服务文件后，用 `sudo systemctl edit capswriter-gateway` 加一段覆盖，把启动命令末尾加上 `--stream-model /srv/capswriter/private/stream-model`，然后 `sudo systemctl daemon-reload && sudo systemctl restart capswriter-gateway`。

不加 `--stream-model` 时网关照常工作，只是没有草稿。

## 真机验收

- 电脑或 AWS 更新并启用草稿后，录一段 10 秒左右的话：说话时键盘顶部应在约 1 秒内开始出现草稿，并随说话增长；草稿太长时显示最新的部分。
- 点停止后，草稿保留到准确结果出来，然后准确结果打进输入框，顶部恢复提示文字。
- 输入框模式下，在备忘录、微信、Claude、浏览器地址栏各试一次：草稿带下划线出现并随说话变化；停止后被准确结果替换，没有残留、没有重复；录音中切走再回来，输入框里没有残留草稿；录音中按删除或空格，草稿先消失，之后的新草稿出现在光标处。
- 录一段 2 分钟以上的话：停止后应很快出结果（不再有长时间的上传等待）。
- 录音中短暂断网几秒：草稿暂停，恢复网络后追上；最终结果不丢字。
- 服务没加 `--stream-model`：一切照旧，只是没有草稿。

## 已知限制

- 草稿比说话慢约 1 秒（手机每 0.35 秒发一次、键盘每 0.45 秒查一次，再加网络和 Tailscale）。
- 草稿模型准确度明显不如最终模型，会有错字、“呃”之类；它只是让你知道“在听、听到了什么”。
- 顶部模式下草稿只显示一行（最新的部分）。
- 输入框模式下，如果录音时你点了输入框别处，有的 App 可能把草稿当成正式文字留下，最终结果就会重复一份。遇到时点撤回，或切到顶部模式，并记下是哪个 App。
- 草稿模型来自 FunASR 的流式 Paraformer（sherpa-onnx 转换版，Apache-2.0）。以后若做商业版，需要再核对 FunASR 原模型的许可条款。
