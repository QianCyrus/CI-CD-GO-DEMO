package service

import (
	"context"
	"errors"
	"strings"
)

var ErrInvalidName = errors.New("invalid name")

type Greeter interface {
	Hello(ctx context.Context, name string) (string, error)
}

type GreeterService struct{}

func NewGreeterService() *GreeterService {
	return &GreeterService{}
}

func (s *GreeterService) Hello(ctx context.Context, name string) (string, error) {
	_ = ctx

	name = strings.TrimSpace(name)
	if name == "" {
		return "", ErrInvalidName
	}
	if len(name) > 64 {
		return "", ErrInvalidName
	}

	return "Hello, " + name + "!", nil
}

