class Paths < Formula
  desc "CLI tool to display PATH directories with colors and interactive selector"
  homepage "https://github.com/begoon/zig-path"
  version "0.1.0"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/begoon/zig-path/releases/download/latest/paths-macos-arm64.tar.gz"
      sha256 "9eaaca6bfe5abdc9dfd26a020f0482df8a3649b58279f2d4c6b18740bfa72ecc"
    else
      url "https://github.com/begoon/zig-path/releases/download/latest/paths-macos-x86_64.tar.gz"
      sha256 "c1f64892efe33781180438f3255558a3c29e322b5a8a9c17f1b7829cff1745e9"
    end
  end

  def install
    bin.install "paths"
  end

  test do
    assert_match(/\/usr\/bin/, shell_output("#{bin}/paths"))
  end
end
