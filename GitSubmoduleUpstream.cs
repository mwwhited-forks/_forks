using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

/// <summary>
/// Git Submodule Upstream Remote Configuration Tool
/// 
/// Configures upstream remotes for git submodules based on an extended .gitmodules file.
/// 
/// Usage:
///   GitSubmoduleUpstream [gitmodulesPath] [--dry-run] [--verbose]
/// 
/// Example:
///   GitSubmoduleUpstream
///   GitSubmoduleUpstream .gitmodules --dry-run
/// </summary>
class Program
{
    static async Task<int> Main(string[] args)
    {
        var options = ParseArguments(args);
        
        if (!File.Exists(options.GitmodulesPath))
        {
            Console.Error.WriteLine($"Error: .gitmodules file not found at: {options.GitmodulesPath}");
            return 1;
        }

        Console.WriteLine($"Reading .gitmodules from: {options.GitmodulesPath}\n");

        try
        {
            var submodules = ParseGitmodules(options.GitmodulesPath);
            var stats = await ProcessSubmodulesAsync(submodules, options);

            PrintSummary(stats);
            return stats.ErrorCount > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Fatal error: {ex.Message}");
            if (options.Verbose)
            {
                Console.Error.WriteLine(ex.StackTrace);
            }
            return 1;
        }
    }

    static Options ParseArguments(string[] args)
    {
        var options = new Options
        {
            GitmodulesPath = ".gitmodules",
            DryRun = false,
            Verbose = false
        };

        foreach (var arg in args)
        {
            if (arg == "--dry-run")
                options.DryRun = true;
            else if (arg == "--verbose")
                options.Verbose = true;
            else if (!arg.StartsWith("--"))
                options.GitmodulesPath = arg;
        }

        return options;
    }

    static Dictionary<string, Submodule> ParseGitmodules(string path)
    {
        var content = File.ReadAllText(path);
        var submodules = new Dictionary<string, Submodule>();
        var currentModule = (string)null;
        var currentSubmodule = new Submodule();

        var lines = content.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None);

        foreach (var line in lines)
        {
            var trimmed = line.Trim();

            // Match [submodule "name"] sections
            var moduleMatch = Regex.Match(trimmed, @"^\[submodule ""([^""]+)""\]");
            if (moduleMatch.Success)
            {
                if (currentModule != null)
                {
                    submodules[currentModule] = currentSubmodule;
                }

                currentModule = moduleMatch.Groups[1].Value;
                currentSubmodule = new Submodule { Name = currentModule };
                continue;
            }

            // Match key = value pairs
            var kvMatch = Regex.Match(trimmed, @"^(\w+)\s*=\s*(.+)$");
            if (kvMatch.Success && currentModule != null)
            {
                var key = kvMatch.Groups[1].Value;
                var value = kvMatch.Groups[2].Value.Trim();

                switch (key)
                {
                    case "path":
                        currentSubmodule.Path = value;
                        break;
                    case "url":
                        currentSubmodule.Url = value;
                        break;
                    case "upstream":
                        currentSubmodule.Upstream = value;
                        break;
                }
            }
        }

        // Don't forget the last module
        if (currentModule != null)
        {
            submodules[currentModule] = currentSubmodule;
        }

        return submodules;
    }

    static async Task<Statistics> ProcessSubmodulesAsync(
        Dictionary<string, Submodule> submodules,
        Options options)
    {
        var stats = new Statistics();
        var tasks = new List<Task>();

        foreach (var kvp in submodules.OrderBy(x => x.Key))
        {
            var moduleName = kvp.Key;
            var module = kvp.Value;

            if (string.IsNullOrEmpty(module.Path))
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"⚠ Skipping '{moduleName}': no path defined");
                Console.ResetColor();
                stats.SkipCount++;
                continue;
            }

            if (string.IsNullOrEmpty(module.Upstream))
            {
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"⚠ Skipping '{moduleName}': no upstream URL defined");
                Console.ResetColor();
                stats.SkipCount++;
                continue;
            }

            // Process sequentially to maintain output order
            await ProcessModuleAsync(moduleName, module, options, stats);
        }

        return stats;
    }

    static async Task ProcessModuleAsync(
        string moduleName,
        Submodule module,
        Options options,
        Statistics stats)
    {
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"Processing: {moduleName}");
        Console.ResetColor();
        Console.WriteLine($"  Path:     {module.Path}");
        Console.WriteLine($"  Upstream: {module.Upstream}");

        // Validate submodule directory exists
        if (!Directory.Exists(module.Path))
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"  ⚠ Skipping: path not found '{module.Path}'");
            Console.ResetColor();
            stats.SkipCount++;
            Console.WriteLine();
            return;
        }

        // Validate .git directory exists
        var gitDir = Path.Combine(module.Path, ".git");
        if (!Directory.Exists(gitDir))
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"  ⚠ Skipping: .git directory not found (submodule may not be initialized)");
            Console.ResetColor();
            stats.SkipCount++;
            Console.WriteLine();
            return;
        }

        try
        {
            // Check if upstream remote already exists
            var currentUpstream = await GetGitRemoteUrlAsync(module.Path, "upstream");

            if (currentUpstream != null)
            {
                if (currentUpstream == module.Upstream)
                {
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("  ✓ Status:   Upstream already configured correctly");
                    Console.ResetColor();
                    stats.SuccessCount++;
                }
                else
                {
                    Console.ForegroundColor = ConsoleColor.Yellow;
                    Console.WriteLine("  ⚠ Warning:  Upstream remote exists with different URL");
                    Console.WriteLine($"    Current:  {currentUpstream}");
                    Console.WriteLine($"    Expected: {module.Upstream}");
                    Console.ResetColor();

                    if (options.DryRun)
                    {
                        Console.ForegroundColor = ConsoleColor.Gray;
                        Console.WriteLine("    [DRY RUN] Would update remote");
                        Console.ResetColor();
                    }
                    else
                    {
                        await ExecuteGitCommandAsync(module.Path, "remote", "set-url", "upstream", module.Upstream);
                        Console.ForegroundColor = ConsoleColor.Green;
                        Console.WriteLine("  ✓ Status:   Upstream remote updated");
                        Console.ResetColor();
                    }

                    stats.SuccessCount++;
                }
            }
            else
            {
                if (options.DryRun)
                {
                    Console.ForegroundColor = ConsoleColor.Gray;
                    Console.WriteLine("  [DRY RUN] Would add upstream remote");
                    Console.ResetColor();
                }
                else
                {
                    await ExecuteGitCommandAsync(module.Path, "remote", "add", "upstream", module.Upstream);
                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.WriteLine("  ✓ Status:   Upstream remote added");
                    Console.ResetColor();
                }

                stats.SuccessCount++;
            }
        }
        catch (Exception ex)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine($"  ✗ Error:    {ex.Message}");
            Console.ResetColor();
            stats.ErrorCount++;
        }

        Console.WriteLine();
    }

    static async Task<string> GetGitRemoteUrlAsync(string workingDirectory, string remoteName)
    {
        try
        {
            var output = await ExecuteGitCommandAsync(workingDirectory, "remote", "get-url", remoteName);
            return string.IsNullOrWhiteSpace(output) ? null : output.Trim();
        }
        catch
        {
            return null;
        }
    }

    static async Task<string> ExecuteGitCommandAsync(string workingDirectory, params string[] args)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        foreach (var arg in args)
        {
            psi.ArgumentList.Add(arg);
        }

        using (var process = Process.Start(psi))
        {
            var output = await process.StandardOutput.ReadToEndAsync();
            var error = await process.StandardError.ReadToEndAsync();
            
            process.WaitForExit();

            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException($"Git command failed: {error}");
            }

            return output;
        }
    }

    static void PrintSummary(Statistics stats)
    {
        Console.WriteLine(new string('=', 38));
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("Summary:");
        Console.ResetColor();
        Console.WriteLine($"  Processed: {stats.SuccessCount}");
        Console.WriteLine($"  Skipped:   {stats.SkipCount}");
        
        if (stats.ErrorCount > 0)
        {
            Console.ForegroundColor = ConsoleColor.Yellow;
            Console.WriteLine($"  Errors:    {stats.ErrorCount}");
            Console.ResetColor();
        }
        else
        {
            Console.ForegroundColor = ConsoleColor.Green;
            Console.WriteLine($"  Errors:    {stats.ErrorCount}");
            Console.ResetColor();
        }
    }

    class Options
    {
        public string GitmodulesPath { get; set; }
        public bool DryRun { get; set; }
        public bool Verbose { get; set; }
    }

    class Submodule
    {
        public string Name { get; set; }
        public string Path { get; set; }
        public string Url { get; set; }
        public string Upstream { get; set; }
    }

    class Statistics
    {
        public int SuccessCount { get; set; } = 0;
        public int SkipCount { get; set; } = 0;
        public int ErrorCount { get; set; } = 0;
    }
}
