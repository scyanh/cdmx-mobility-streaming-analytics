FROM node:22-slim
RUN npm install -g @dataform/cli@3.0.71 && npm cache clean --force
WORKDIR /dataform
COPY workflow_settings.yaml ./
COPY definitions ./definitions
# Compiling at build time downloads the pinned @dataform/core and fails the build on SQLX errors.
RUN dataform compile >/dev/null
# Credentials come from the job's service account; the CLI only needs project and location.
CMD ["sh", "-c", "printf '{\"projectId\":\"%s\",\"location\":\"%s\"}' \"$PROJECT\" \"${BQ_LOCATION:-US}\" > .df-credentials.json && dataform run"]
