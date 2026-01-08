package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/example/cicd-go-demo/backend/internal/service"
)

func TestHealthz(t *testing.T) {
	t.Parallel()

	h := NewRouter(service.NewGreeterService(), BuildInfo{Version: "dev", Commit: "none", Date: "unknown"})

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("unexpected body: %v", body)
	}
}

func TestHello_OK(t *testing.T) {
	t.Parallel()

	h := NewRouter(service.NewGreeterService(), BuildInfo{Version: "v1", Commit: "c", Date: "d"})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/hello?name=world", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}

	var resp helloResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if resp.Message != "Hello, world!" {
		t.Fatalf("unexpected message: %q", resp.Message)
	}
	if resp.Meta.Version != "v1" || resp.Meta.Commit != "c" || resp.Meta.Date != "d" {
		t.Fatalf("unexpected meta: %+v", resp.Meta)
	}
}

func TestHello_MissingName(t *testing.T) {
	t.Parallel()

	h := NewRouter(service.NewGreeterService(), BuildInfo{Version: "dev", Commit: "none", Date: "unknown"})

	req := httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

