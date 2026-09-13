class ShellcheckLegibility < Formula
  desc "Bash legibility checks that sit beside ShellCheck"
  homepage "https://github.com/yowainwright/shellcheck_legibility"
  url "https://github.com/yowainwright/shellcheck_legibility/releases/" \
      "download/v0.2.1/shellcheck-legibility-0.2.1.tar.gz"
  sha256 "137942db1000e72ce8f8e2fbe8c10e33" \
         "4c70dc554ad2ef08aa49f0778f0302c0"
  license "MIT"
  head "https://github.com/yowainwright/shellcheck_legibility.git", branch: "main"

  def install
    libexec.install "bin", "lib"
    bin.write_exec_script libexec/"bin/shellcheck-legibility"
  end

  test do
    (testpath/"example.sh").write <<~SHELL
      #!/usr/bin/env bash
      build_user() {
        if [[ -n "$USER" ]]; then
          printf '%s\\n' "$USER"
        fi
      }
    SHELL

    system bin/"shellcheck-legibility", "check", testpath/"example.sh", "--exit-zero"
  end
end
