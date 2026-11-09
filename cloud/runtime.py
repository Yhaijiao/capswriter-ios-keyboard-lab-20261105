"""Headless Linux launch shims; recognition and formatting source stays private."""
from __future__ import annotations
import argparse
import importlib
import logging
import multiprocessing
import os
from pathlib import Path
import signal
import sys
import types


def configure(private_root):
    root = Path(private_root).resolve()
    if not (root / 'config_server.py').is_file(): raise ValueError('Private server source missing')
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(root))
    # Avoid importing Windows tray code and prevent transcript file handlers.
    logging.disable(logging.CRITICAL)
    quiet = logging.getLogger('capswriter-private-runtime')
    quiet.addHandler(logging.NullHandler())
    logger_module = types.ModuleType('core.logger')
    logger_module.get_logger = lambda *args, **kwargs: quiet
    logger_module.setup_logger = lambda *args, **kwargs: quiet
    core = types.ModuleType('core'); core.__path__ = [str(root / 'core')]
    core.get_logger = logger_module.get_logger; core.setup_logger = logger_module.setup_logger
    sys.modules['core'] = core; sys.modules['core.logger'] = logger_module
    ui = types.ModuleType('core.server.ui'); ui.__path__ = [str(root / 'core/server/ui')]
    sys.modules['core.server.ui'] = ui
    config = importlib.import_module('config_server')
    config.ServerConfig.addr = '127.0.0.1'; config.ServerConfig.port = '6016'
    config.ServerConfig.enable_tray = False; config.ServerConfig.gpu_boost_enabled = False
    config.ServerConfig.model_type = 'qwen_asr'; config.ServerConfig.log_level = 'CRITICAL'
    model_root = root / 'models/Qwen3-ASR/Qwen3-ASR-1.7B'
    config.ModelPaths.qwen3_asr_gguf_dir = model_root
    for suffix, name in [('encoder_frontend', 'qwen3_asr_encoder_frontend.onnx'),
                         ('encoder_backend', 'qwen3_asr_encoder_backend.onnx'),
                         ('llm_decode', 'qwen3_asr_llm.gguf')]:
        setattr(config.ModelPaths, 'qwen3_asr_gguf_' + suffix, model_root / name)
    config.Qwen3ASRGGUFArgs.model_dir = str(model_root)
    # CAPSWRITER_GPU=1 offloads the llama.cpp decoder to the GPU (needs the CUDA
    # libraries from install_native.py --archive). The ONNX encoder stays on CPU.
    use_gpu = os.environ.get('CAPSWRITER_GPU', '0') == '1'
    config.Qwen3ASRGGUFArgs.onnx_provider = 'CPU'; config.Qwen3ASRGGUFArgs.llm_use_gpu = use_gpu
    config.Qwen3ASRGGUFArgs.verbose = False
    threads = int(os.environ.get('CAPSWRITER_LLM_THREADS', '1'))
    if threads not in (1, 2): raise ValueError('Trial supports one or two decoder threads')
    from core.server.engines.qwen_asr_gguf.inference import llama as native
    original_init = native.LlamaContext.__init__
    def context_init(self, *args, **kwargs):
        kwargs.setdefault('n_threads', threads)
        kwargs.setdefault('n_threads_batch', 2)
        original_init(self, *args, **kwargs)
    native.LlamaContext.__init__ = context_init
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-root', type=Path, required=True)
    args = parser.parse_args()
    if sys.platform != 'linux': raise SystemExit('Linux runtime only')
    # The private server uses multiprocessing. Keep configured modules in workers.
    multiprocessing.set_start_method('fork', force=True)
    configure(args.private_root)
    from core.server.app import CapsWriterServer
    server = CapsWriterServer()
    # The upstream SIGINT handler is interactive; systemd uses SIGTERM instead.
    signal.signal(signal.SIGTERM, lambda *_: server.stop())
    server.start()


if __name__ == '__main__': main()
