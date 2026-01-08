# syntax=docker/dockerfile:1.7

FROM golang:1.23-alpine AS build

WORKDIR /src

RUN apk add --no-cache ca-certificates git

# 先拷贝 go.mod/go.sum，最大化利用 Docker layer cache
COPY go.mod go.sum ./
RUN go mod download

COPY . ./

ARG VERSION=dev
ARG COMMIT=none
ARG DATE=unknown

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath \
  -ldflags="-s -w \
    -X github.com/example/cicd-go-demo/backend/internal/buildinfo.Version=${VERSION} \
    -X github.com/example/cicd-go-demo/backend/internal/buildinfo.Commit=${COMMIT} \
    -X github.com/example/cicd-go-demo/backend/internal/buildinfo.Date=${DATE}" \
  -o /out/server ./cmd/server

# 运行镜像尽量小且无 shell（减少攻击面）
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

WORKDIR /
COPY --from=build /out/server /server

ENV PORT=8080
EXPOSE 8080

USER nonroot:nonroot
ENTRYPOINT ["/server"]

