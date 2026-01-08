package httpapi

import (
	"net/http"
)

type BuildInfo struct {
	Version string
	Commit  string
	Date    string
}

func NewRouter(greeter Greeter, bi BuildInfo) http.Handler {
	api := &API{
		Greeter: greeter,
		Build:   bi,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", api.handleHealthz)
	mux.HandleFunc("GET /api/v1/hello", api.handleHello)

	return mux
}

