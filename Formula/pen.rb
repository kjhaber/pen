class Pen < Formula
  desc "Run coding harnesses (Claude Code, etc.) inside isolated Docker containers"
  homepage "https://github.com/kjhaber/pen"
  url "%%URL%%"
  sha256 "%%SHA256%%"
  license "MIT"

  def install
    inreplace "pen", "%%VERSION%%", version.to_s
    bin.install "pen"
    bash_completion.install "completions/pen.bash"
    zsh_completion.install "completions/_pen"
  end

  test do
    system "bash", "-n", bin/"pen"
  end
end
