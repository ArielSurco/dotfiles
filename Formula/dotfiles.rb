class Dotfiles < Formula
  desc "Shell aliases and utilities for development workflows"
  homepage "https://github.com/ArielSurco/dotfiles"
  url "https://github.com/ArielSurco/dotfiles/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "f5ac4f453d27e89f09dcd00ebb026415fe8ba90127103621c8ea1446d8abaf0b"  # Updated on release
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
