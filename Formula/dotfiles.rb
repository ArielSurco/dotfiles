class Dotfiles < Formula
  desc "Shell aliases and utilities for development workflows"
  homepage "https://github.com/ArielSurco/dotfiles"
  url "https://github.com/ArielSurco/dotfiles/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "e75c76767669f6440c458d37198f131401b2d39aec9240e0eef9e052ab2cf37d"
  license "MIT"

  depends_on "gum"

  def install
    prefix.install Dir["aliases"]
    prefix.install Dir["docs"]
    bin.install "bin/dotfiles-setup"
  end

  def caveats
    <<~EOS
      1. Run `dotfiles-setup` to select which alias groups to enable.

      2. Add this line to your .zshrc:
           source #{prefix}/aliases/init.sh

      3. Reload your shell or run `source ~/.zshrc`
    EOS
  end

  test do
    assert_match "init.sh", shell_output("ls #{prefix}/aliases/")
  end
end
