# InvokeAI Quick Startup (Docker Compose)

This project provides a streamlined Docker Compose setup for running [InvokeAI](https://invoke-ai.github.io/InvokeAI/), a creative engine for Stable Diffusion models. It includes utilities and configuration to get you up and running quickly with persistent storage for models and outputs.

## Getting Started

1.  **Prerequisites**: Ensure you have Docker and Docker Compose installed on your system.
2.  **Configuration**: 
    -   Review `docker-compose.yml` for simplified environment variable management.
    -   (Optional) Create a `.env` file to override default environment variables (see Options below).
3.  **Run**:
    ```bash
    docker compose up -d
    ```
4.  **Access**: Open your browser and navigate to `http://localhost:9090`.

## Configuration Options

### Docker Environment Variables
These variables control the container setup and volume mappings. You can set them in a `.env` file or export them in your shell.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `INVOKEAI_PORT` | The port the service runs on. | `9090` |
| `HOST_INVOKEAI_ROOT` | Local host directory for InvokeAI data persistence. | `~/invokeai` |
| `CONTAINER_UID` | User ID to run the container as (fixes permission issues). | `1000` |
| `HF_HOME` | Cache directory for HuggingFace models. | `~/.cache/huggingface` |
| `HF_ENDPOINT` | Mirror endpoint for HuggingFace (for region-specific access). | `https://hf-mirror.com` |

### InvokeAI Application Settings
Configure the application behavior in `data/app-data/invokeai.yaml`.

### InvokeAI Application Settings
Configure the application behavior in `data/app-data/invokeai.yaml`.

| Setting | Type | Description |
| :--- | :--- | :--- |
| `host` | str | IP address to bind to. Use 0.0.0.0 to serve to your local network. |
| `port` | int | Port to bind to. |
| `allow_origins` | list[str] | Allowed CORS origins. |
| `allow_credentials` | bool | Allow CORS credentials. |
| `allow_methods` | list[str] | Methods allowed for CORS. |
| `allow_headers` | list[str] | Headers allowed for CORS. |
| `ssl_certfile` | Optional[Path] | SSL certificate file for HTTPS. |
| `ssl_keyfile` | Optional[Path] | SSL key file for HTTPS. |
| `models_dir` | Path | Path to the models directory. |
| `outputs_dir` | Path | Path to directory for outputs. |
| `db_dir` | Path | Path to InvokeAI databases directory. |
| `custom_nodes_dir` | Path | Path to directory for custom nodes. |
| `style_presets_dir` | Path | Path to directory for style presets. |
| `workflow_thumbnails_dir` | Path | Path to directory for workflow thumbnails. |
| `download_cache_dir` | Path | Path to the directory that contains dynamically downloaded models. |
| `convert_cache_dir` | Path | Path to the converted models cache directory (DEPRECATED). |
| `legacy_conf_dir` | Path | Path to directory of legacy checkpoint config files. |
| `device` | str | Preferred execution device (auto, cpu, cuda, mps, cuda:N). |
| `precision` | str | Floating point precision (auto, float16, bfloat16, float32). |
| `max_cache_vram_gb` | Optional[float] | The amount of VRAM to use for model caching in GB. |
| `max_cache_ram_gb` | Optional[float] | The maximum amount of CPU RAM to use for model caching in GB. |
| `device_working_mem_gb` | float | The amount of working memory to keep available on the compute device (in GB). |
| `model_cache_keep_alive_min` | float | How long to keep models in cache after last use, in minutes. |
| `enable_partial_loading` | bool | Enable partial loading of models to reduce VRAM requirements. |
| `keep_ram_copy_of_weights` | bool | Keep a full RAM copy of a model's weights when loaded in VRAM. |
| `attention_type` | str | Attention type (auto, normal, xformers, sliced, torch-sdp). |
| `attention_slice_size` | str | Slice size, valid when attention_type=="sliced". |
| `sequential_guidance` | bool | Calculate guidance in serial instead of parallel. |
| `force_tiled_decode` | bool | Enable tiled VAE decode (reduces memory consumption). |
| `pytorch_cuda_alloc_conf` | Optional[str] | Configure the Torch CUDA memory allocator. |
| `patchmatch` | bool | Enable patchmatch inpaint code. |
| `log_level` | str | Emit logging messages at this level or higher (debug, info, warning, error, critical). |
| `log_handlers` | list[str] | Log handler options ("console", "file=", "syslog=...", "http="). |
| `log_format` | str | Log format (plain, color, syslog, legacy). |
| `log_tokenization` | bool | Enable logging of parsed prompt tokens. |
| `log_memory_usage` | bool | Log a memory snapshot before and after every model cache operation. |
| `log_sql` | bool | Log SQL queries. |
| `log_level_network` | str | Log level for network-related messages. |
| `dev_reload` | bool | Automatically reload when Python sources are changed. |
| `profile_graphs` | bool | Enable graph profiling using cProfile. |
| `profile_prefix` | Optional[str] | An optional prefix for profile output files. |
| `profiles_dir` | Path | Path to profiles output directory. |
| `max_queue_size` | int | Maximum number of items in the session queue. |
| `clear_queue_on_startup` | bool | Empties session queue on startup. |
| `node_cache_size` | int | How many cached nodes to keep in memory. |
| `allow_nodes` | Optional[list[str]] | List of nodes to allow. |
| `deny_nodes` | Optional[list[str]] | List of nodes to deny. |
| `pil_compress_level` | int | PNG compression level (0-9). |
| `hashing_algorithm` | str | Model hashing algorithm for model installs (blake3_single, etc.). |
| `remote_api_tokens` | Optional[list] | List of regex and token pairs for model downloads. |
| `scan_models_on_startup` | bool | Scan the models directory on startup. |
| `allow_unknown_models` | bool | Allow installation of models that we are unable to identify. |
| `unsafe_disable_picklescan` | bool | UNSAFE. Disable the picklescan security check. |
| `use_memory_db` | bool | Use in-memory database. |

### Low VRAM Configuration
For systems with limited VRAM (e.g., <8GB for SDXL, or running FLUX), you can enable partial loading to stream models from RAM to VRAM.

1.  **Enable Partial Loading**:
    Add the following to your `data/app-data/invokeai.yaml`:
    ```yaml
    enable_partial_loading: true
    ```

2.  **Fine-tuning (Optional)**:
    -   `pytorch_cuda_alloc_conf: "backend:cudaMallocAsync"`: Reduces peak reserved VRAM, recommended for many systems.
    -   `max_cache_ram_gb`: Increases RAM used for caching inactive models. Recommended: Total System RAM - 4GB.
    -   `device_working_mem_gb`: Default is 3GB. Increase (e.g., to 4) if you encounter OOM errors during VAE decode.
    -   `max_cache_vram_gb`: **Advanced**. Manually limit VRAM for model caching. Only set if you need to reserve VRAM for other applications, otherwise let InvokeAI manage it dynamically.

For a full list of options, refer to the [official documentation](https://invoke-ai.github.io/InvokeAI/configuration/).
