# Filestash Docker Setup

Web-based file browser for accessing a host directory through your browser.

## Quick Start

```bash
cd filestash
# Copy `env.example` to `.env` and adjust values (UID/GID, ports, and the host directory you want to browse).
cp -n env.example .env
docker compose up -d
```

## Access

Open your browser to:
- `http://<host>:11088` (redirects to HTTPS)
- `https://<host>:11089`

If you changed ports in `.env`, use those values instead.

## Configuration Details

### APPLICATION_URL Format
`APPLICATION_URL` (optional) sets Filestash's public host (`general.host`) and is used when it needs to generate absolute URLs (eg: share links / redirects).
When running behind a reverse proxy (nginx), you can usually leave it unset so Filestash relies on incoming `Host` and `X-Forwarded-*` headers instead.

### On First Launch

1. Navigate to http://localhost:11088
2. Set up an admin password when prompted
3. Configure a storage backend:
   - Click "Add Storage" or go to Settings
   - Select "Local Filesystem" as the backend
   - Set the path to `/data` (this maps to `/data2/huangzhe` on your host)
   - Save the configuration

### Mounted Data

- **Host path**: `${FILESTASH_DATA_DIR}` (from `.env`)
- **Container path**: `/data`
- **Permissions**: Read-Write (rw)

When configuring Filestash's local filesystem backend, use `/data` as the root path.

## Common Commands

```bash
# Start the service
docker compose up -d

# Stop the service
docker compose down

# View logs
docker compose logs -f

# Restart the service
docker compose restart

# Update to latest version
docker compose pull
docker compose up -d
```

## Volumes

- Docker volume `filestash_appdata` - Persistent application data (config, database, logs, certs)
- `${FILESTASH_DATA_DIR}` → `/data` - Your data directory

## Features

- Markdown preview
- Image, video, audio streaming (with transcoding)
- PDF viewer
- Code editor with syntax highlighting
- Multi-user support
- Chromecast support
- No download required for preview

## Troubleshooting

### Cannot access files

Make sure you've configured the storage backend to point to `/data` in the Filestash settings.

### Port already in use

Change the port mapping in `docker-compose.yml`:
```yaml
ports:
  - "YOUR_PORT:8334"
```

### Permission issues

Check that the container can access your mounted host directory:
```bash
docker compose exec filestash ls -la /data
```

## References

- [Filestash Official Docs](https://www.filestash.app/docs/)
- [Docker Hub](https://hub.docker.com/r/machines/filestash/)
- [GitHub](https://github.com/mickael-kerjean/filestash)
