class DenoteTasks < Formula
  desc "Task management tool using Denote file naming convention"
  homepage "https://github.com/pdxmph/denote-tasks"
  version "0.14.1"
  license "MIT"
  
  # Use binary release for ARM64 Macs
  if OS.mac? && Hardware::CPU.arm?
    url "https://github.com/pdxmph/denote-tasks/releases/download/v0.14.1/denote-tasks_v0.14.1_darwin_arm64.tar.gz"
    sha256 "1dc50281130fcf9b37d84abff0a361940e1cb5abe85211a50aeee33a3c072a18"
  else
    # Fall back to building from source
    url "https://github.com/pdxmph/denote-tasks/archive/refs/tags/v0.14.1.tar.gz"
    sha256 "26715011d330b8bd129c75bb5c280efe836d2f8d74ea027ba6d0a3bfea984ee4"
    depends_on "go" => :build
  end
  
  depends_on arch: :arm64  # Currently only ARM64 builds available

  def install
    if File.exist?("go.mod")
      # Building from source
      system "go", "build", *std_go_args(ldflags: "-s -w")
      
      # Install completions from source
      bash_completion.install "completions/denote-tasks.bash"
      zsh_completion.install "completions/_denote-tasks"
    else
      # Installing pre-built binary
      bin.install "denote-tasks"
      
      # Install completions from binary archive
      bash_completion.install "completions/denote-tasks.bash" if File.exist?("completions/denote-tasks.bash")
      zsh_completion.install "completions/_denote-tasks" if File.exist?("completions/_denote-tasks")
    end
    
    # Install documentation
    doc.install "README.md" if File.exist?("README.md")
  end

  def caveats
    <<~EOS
      To use denote-tasks, create ~/.config/denote-tasks/config.toml with:

        notes_directory = "~/tasks"
        editor = "vim"  # or your preferred editor
    EOS
  end

  test do
    assert_match "denote-tasks", shell_output("#{bin}/denote-tasks --help 2>&1")
  end
end