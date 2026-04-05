class ClaudeDevcon < Formula
  desc "Run Claude Code inside an isolated Docker container"
  homepage "https://github.com/kjhaber/claude-devcon"
  url "%%URL%%"
  sha256 "%%SHA256%%"
  license "MIT"

  def install
    bin.install "claude-devcon"
    bash_completion.install "completions/claude-devcon.bash"
    zsh_completion.install "completions/_claude-devcon"
  end

  test do
    system "bash", "-n", bin/"claude-devcon"
  end
end
