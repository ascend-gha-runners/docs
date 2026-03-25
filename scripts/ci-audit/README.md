# CI Cache Audit Script

A utility to scan multiple GitHub repositories and verify if their workflows are configured with specific PyPI and APT cache services.

## Usage

1. Create a `repos.txt` file with one `org/repo` per line.
2. Run the script:
   ```bash
   ./check_cache.sh repos.txt
   ```

## Configuration

The script uses environment variables to specify the search keywords, allowing you to avoid hardcoding internal service addresses.

| Variable | Description | Default |
| :--- | :--- | :--- |
| `PYPI_CACHE_KEYWORD` | The keyword to match PyPI cache usage | `cache-service.nginx-pypi-cache` |
| `APT_CACHE_PATTERN` | The regex pattern to match APT cache usage | `:8081\|apt.*cache-service` |

Example with custom settings:
```bash
export PYPI_CACHE_KEYWORD="my-internal-pypi-cache"
export APT_CACHE_PATTERN=":8081"
./check_cache.sh repos.txt
```

## Output

The script outputs a Markdown-formatted table showing which repositories, branches, and workflow files have the cache configurations enabled.
