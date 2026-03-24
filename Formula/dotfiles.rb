class Dotfiles < Formula
  desc "Shell aliases and utilities for development workflows"
  homepage "https://github.com/ArielSurco/dotfiles"
  url "https://github.com/ArielSurco/dotfiles/archive/refs/tags/v1.1.0.tar.gz"
  sha256 "5f098342b7eda90aaa9b5349b1f2643ef77d6edfdc2445d5bdb821613a1afb60"
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
