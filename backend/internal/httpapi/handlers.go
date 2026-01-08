package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/example/cicd-go-demo/backend/internal/service"
)

// Greeter 通过接口把 transport 与业务逻辑解耦，便于单测（这里就是“分层”的核心点）。
type Greeter interface {
	Hello(ctx context.Context, name string) (string, error)
}

type API struct {
	Greeter Greeter
	Build   BuildInfo
}

type helloResponse struct {
	Message string         `json:"message"`
	Meta    helloMetaBlock `json:"meta"`
}

type helloMetaBlock struct {
	Version string `json:"version"`
	Commit  string `json:"commit"`
	Date    string `json:"date"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func (a *API) handleHealthz(w http.ResponseWriter, r *http.Request) {
	_ = r
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *API) handleHello(w http.ResponseWriter, r *http.Request) {
	name := r.URL.Query().Get("name")
	if name == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing query param: name"})
		return
	}

	msg, err := a.Greeter.Hello(r.Context(), name)
	if err != nil {
		// 这里只演示一个最常见的错误映射：用户输入不合法 -> 400
		if errors.Is(err, service.ErrInvalidName) {
			writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid name"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "internal error"})
		return
	}

	writeJSON(w, http.StatusOK, helloResponse{
		Message: msg,
		Meta: helloMetaBlock{
			Version: a.Build.Version,
			Commit:  a.Build.Commit,
			Date:    a.Build.Date,
		},
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

