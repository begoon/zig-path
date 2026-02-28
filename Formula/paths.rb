class Paths < Formula
  desc "CLI tool to display PATH directories with colors and interactive selector"
  homepage "https://github.com/begoon/zig-path"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/begoon/zig-path/releases/download/latest/paths-macos-arm64.tar.gz"
    else
      url "https://github.com/begoon/zig-path/releases/download/latest/paths-macos-x86_64.tar.gz"
    end
  end

  def install
    bin.install "paths"
  end

  test do
    assert_match(/\/usr\/bin/, shell_output("#{bin}/paths"))
  end
end
