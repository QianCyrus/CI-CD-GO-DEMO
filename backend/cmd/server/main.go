package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/example/cicd-go-demo/backend/internal/buildinfo"
	"github.com/example/cicd-go-demo/backend/internal/config"
	"github.com/example/cicd-go-demo/backend/internal/httpapi"
	"github.com/example/cicd-go-demo/backend/internal/service"
)

func main() {
	cfg := config.Load()

	bi := httpapi.BuildInfo{
		Version: buildinfo.Version,
		Commit:  buildinfo.Commit,
		Date:    buildinfo.Date,
	}

	handler := httpapi.NewRouter(service.NewGreeterService(), bi)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       cfg.ReadTimeout,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
	}

	log.Printf("server starting addr=%s version=%s commit=%s date=%s", cfg.Addr, bi.Version, bi.Commit, bi.Date)

	errCh := make(chan error, 1)
	go func() {
		errCh <- srv.ListenAndServe()
	}()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	select {
	case <-ctx.Done():
		log.Printf("shutdown signal received")
	case err := <-errCh:
		if err == nil || err == http.ErrServerClosed {
			return
		}
		log.Fatalf("server error: %v", err)
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}
	log.Printf("server stopped")
}

