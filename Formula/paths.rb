class Paths < Formula
  desc "CLI tool to display PATH directories with colors and interactive selector"
  homepage "https://github.com/begoon/zig-path"
  url "https://github.com/begoon/zig-path.git", branch: "main"
  version "0.1.0"
  license "MIT"

  depends_on "zig" => :build

  def install
    zig_version = Utils.safe_popen_read("zig", "version").strip
    odie "zig 0.16+ required, found #{zig_version}" if Version.new(zig_version) < Version.new("0.16")
    ENV["HOMEBREW_FORMULA_PREFIX"] = prefix.to_s
    system "zig", "build", "--prefix", prefix, "-Doptimize=ReleaseFast"
  end

  test do
    assert_match(/\/usr\/bin/, shell_output("#{bin}/paths"))
  end
end
