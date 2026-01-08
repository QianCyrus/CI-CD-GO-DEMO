package buildinfo

// 这三个变量会在构建时通过 -ldflags 注入（CI/CD 里会示范），本地开发时保持默认值即可。
var (
	Version = "dev"
	Commit  = "none"
	Date    = "unknown"
)

