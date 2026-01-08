package service

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestGreeterService_Hello_OK(t *testing.T) {
	t.Parallel()

	svc := NewGreeterService()
	got, err := svc.Hello(context.Background(), "  world  ")
	if err != nil {
		t.Fatalf("expected nil err, got %v", err)
	}
	if got != "Hello, world!" {
		t.Fatalf("unexpected message: %q", got)
	}
}

func TestGreeterService_Hello_Empty(t *testing.T) {
	t.Parallel()

	svc := NewGreeterService()
	_, err := svc.Hello(context.Background(), "   ")
	if !errors.Is(err, ErrInvalidName) {
		t.Fatalf("expected ErrInvalidName, got %v", err)
	}
}

func TestGreeterService_Hello_TooLong(t *testing.T) {
	t.Parallel()

	svc := NewGreeterService()
	_, err := svc.Hello(context.Background(), strings.Repeat("a", 65))
	if !errors.Is(err, ErrInvalidName) {
		t.Fatalf("expected ErrInvalidName, got %v", err)
	}
}

