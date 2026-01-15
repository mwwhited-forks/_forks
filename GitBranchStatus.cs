using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

/// <summary>
/// Git Branch Status Checker
/// 
/// Shows how many commits each branch is ahead/behind compared to upstream remote
/// 
/// Usage:
///   GitBranchStatus [path] [--remote <name>] [--pattern <glob>] [--all-submodules] [--format <type>]
/// 
/// Example:
///   GitBranchStatus
///   GitBranchStatus ./submodule --remote upstream
///   GitBranchStatus --all-submodules --format json
/// </summary>
class Program
{
    static async Task<int> Main(string[] args)
    {
        var options = ParseArguments(args);

        try
        {
            List<BranchStatus> allResults = new();

            if (options.AllSubmodules)
            {
                Console.WriteLine("Processing all submodules...\n");
                var submodules = ParseSubmodules(options.GitmodulesPath);

                foreach (var submodule in submodules)
                {
                    if (Directory.Exists(submodule.Path))
                    {
                        Console.WriteLine($"Checking: {submodule.Name}...");
                        var results = await GetBranchComparisonAsync(submodule.Path, options.RemoteName, options);
                        allResults.AddRange(results);
                    }
                    else
                    {
                        Console.Error.WriteLine($"⚠ Submodule path not found: {submodule.Path}");
                    }
                }
                Console.WriteLine();
            }
            else
            {
                allResults = await GetBranchComparisonAsync(options.Path, options.RemoteName, options);
            }

            // Format output
            switch (options.Format)
            {
                case OutputFormat.Json:
                    FormatJsonOutput(allResults);
                    break;
                case OutputFormat.Csv:
                    FormatCsvOutput(allResults);
                    break;
                default:
                    FormatTableOutput(allResults);
                    PrintSummary(allResults);
                    break;
            }

            var untrackedCount = allResults.Count(r => !r.TrackingOk);
            return untrackedCount > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error: {ex.Message}");
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
            Path = ".",
            RemoteName = "upstream",
            BranchPattern = "*",
            AllSubmodules = false,
            GitmodulesPath = ".gitmodules",
            Verbose = false,
            Format = OutputFormat.Table
        };

        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--remote":
                    if (i + 1 < args.Length)
                        options.RemoteName = args[++i];
                    break;
                case "--pattern":
                    if (i + 1 < args.Length)
                        options.BranchPattern = args[++i];
                    break;
                case "--all-submodules":
                    options.AllSubmodules = true;
                    break;
                case "--gitmodules":
                    if (i + 1 < args.Length)
                        options.GitmodulesPath = args[++i];
                    break;
                case "--verbose":
                    options.Verbose = true;
                    break;
                case "--format":
                    if (i + 1 < args.Length)
                    {
                        var format = args[++i].ToLower();
                        if (Enum.TryParse<OutputFormat>(format, true, out var fmt))
                            options.Format = fmt;
                    }
                    break;
                case "-h":
                case "--help":
                    PrintHelp();
                    Environment.Exit(0);
                    break;
                default:
                    if (!args[i].StartsWith("--"))
                        options.Path = args[i];
                    break;
            }
        }

        return options;
    }

    static void PrintHelp()
    {
        Console.WriteLine(@"Check git branch ahead/behind status against upstream remote

Usage: GitBranchStatus [path] [options]

Options:
  --remote <name>        Remote name to compare (default: upstream)
  --pattern <glob>       Branch pattern filter (default: *)
  --all-submodules       Check all submodules from .gitmodules
  --gitmodules <path>    Path to .gitmodules file
  --format <type>        Output format: table, json, csv (default: table)
  --verbose              Show detailed information
  -h, --help            Show this help message

Examples:
  GitBranchStatus
  GitBranchStatus ./submodule --remote upstream
  GitBranchStatus --all-submodules --pattern ""feature/*""
  GitBranchStatus --format json");
    }

    static async Task<List<BranchStatus>> GetBranchComparisonAsync(
        string repoPath,
        string remoteName,
        Options options)
    {
        var results = new List<BranchStatus>();

        if (!Directory.Exists(Path.Combine(repoPath, ".git")))
        {
            Console.Error.WriteLine($"Error: Not a git repository: {repoPath}");
            return results;
        }

        var repoName = new DirectoryInfo(repoPath).Name;

        try
        {
            // Fetch from remote
            await ExecuteGitCommandAsync(repoPath, "fetch", remoteName, "--quiet");

            // Get default branch
            var defaultBranch = await ExecuteGitCommandAsync(repoPath, "rev-parse", "--abbrev-ref", "origin/HEAD");
            defaultBranch = defaultBranch?.Split('/').LastOrDefault() ?? "";

            // Get all branches
            var branchesOutput = await ExecuteGitCommandAsync(repoPath, "branch", "--format=%(refname:short)");
            var branches = branchesOutput?.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries) ?? Array.Empty<string>();

            foreach (var branch in branches)
            {
                if (string.IsNullOrWhiteSpace(branch))
                    continue;

                // Match pattern
                if (!MatchPattern(branch, options.BranchPattern))
                    continue;

                // Get local hash
                var localHash = await ExecuteGitCommandAsync(repoPath, "rev-parse", branch);
                if (string.IsNullOrWhiteSpace(localHash))
                    continue;

                localHash = localHash.Substring(0, Math.Min(7, localHash.Length));

                // Get tracking branch
                var tracking = await ExecuteGitCommandAsync(repoPath, "rev-parse", "--abbrev-ref", $"{branch}@{{u}}");

                string remoteBranch = $"{remoteName}/{branch}";

                if (string.IsNullOrWhiteSpace(tracking) || tracking == $"{branch}@{{u}}")
                {
                    // Check if remote branch exists
                    var remoteExists = await ExecuteGitCommandAsync(repoPath, "rev-parse", "--verify", remoteBranch);
                    if (string.IsNullOrWhiteSpace(remoteExists))
                    {
                        results.Add(new BranchStatus
                        {
                            Repository = repoName,
                            Branch = branch,
                            Remote = remoteName,
                            RemoteBranch = "N/A",
                            Ahead = 0,
                            Behind = 0,
                            Status = "⚠ No remote branch",
                            LocalHash = localHash,
                            RemoteHash = "N/A",
                            IsDefault = branch == defaultBranch,
                            TrackingOk = false
                        });
                        continue;
                    }

                    tracking = remoteBranch;
                }

                // Get remote hash
                var remoteHash = await ExecuteGitCommandAsync(repoPath, "rev-parse", tracking);
                if (string.IsNullOrWhiteSpace(remoteHash))
                {
                    results.Add(new BranchStatus
                    {
                        Repository = repoName,
                        Branch = branch,
                        Remote = remoteName,
                        RemoteBranch = tracking,
                        Ahead = 0,
                        Behind = 0,
                        Status = "⚠ Remote not accessible",
                        LocalHash = localHash,
                        RemoteHash = "N/A",
                        IsDefault = branch == defaultBranch,
                        TrackingOk = false
                    });
                    continue;
                }

                remoteHash = remoteHash.Substring(0, Math.Min(7, remoteHash.Length));

                // Calculate ahead/behind
                var aheadBehind = await ExecuteGitCommandAsync(repoPath, "rev-list", "--count", "--left-right", $"{tracking}...{branch}");

                int ahead = 0, behind = 0;
                if (!string.IsNullOrWhiteSpace(aheadBehind))
                {
                    var parts = aheadBehind.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length == 2 && int.TryParse(parts[0], out int b) && int.TryParse(parts[1], out int a))
                    {
                        behind = b;
                        ahead = a;
                    }
                }

                // Determine status
                string status = ahead == 0 && behind == 0 ? "✓ Synced"
                    : ahead > 0 && behind == 0 ? "⬆ Ahead"
                    : ahead == 0 && behind > 0 ? "⬇ Behind"
                    : "⬍ Diverged";

                results.Add(new BranchStatus
                {
                    Repository = repoName,
                    Branch = branch,
                    Remote = remoteName,
                    RemoteBranch = tracking,
                    Ahead = ahead,
                    Behind = behind,
                    Status = status,
                    LocalHash = localHash,
                    RemoteHash = remoteHash,
                    IsDefault = branch == defaultBranch,
                    TrackingOk = true
                });
            }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error processing repository at {repoPath}: {ex.Message}");
        }

        return results;
    }

    static bool MatchPattern(string branch, string pattern)
    {
        if (pattern == "*")
            return true;

        // Simple glob pattern matching
        var regex = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
        return Regex.IsMatch(branch, regex);
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
            psi.ArgumentList.Add(arg);

        using (var process = Process.Start(psi))
        {
            var output = await process.StandardOutput.ReadToEndAsync();
            var error = await process.StandardError.ReadToEndAsync();

            process.WaitForExit();

            if (process.ExitCode != 0 && !args[0].Contains("rev-parse", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException($"Git command failed: {error}");
            }

            return output?.Trim() ?? "";
        }
    }

    static void FormatTableOutput(List<BranchStatus> results)
    {
        if (results.Count == 0)
        {
            Console.WriteLine("No branches found");
            return;
        }

        var grouped = results.GroupBy(r => r.Repository).ToList();

        foreach (var group in grouped)
        {
            Console.WriteLine();
            Console.ForegroundColor = ConsoleColor.Cyan;
            Console.WriteLine(group.Key);
            Console.ResetColor();
            Console.WriteLine(new string('-', 100));

            Console.WriteLine($"{"Branch",-35} {"Status",-20} {"Ahead",10} {"Behind",10}");
            Console.WriteLine(new string('-', 100));

            foreach (var result in group)
            {
                var marker = result.IsDefault ? "◆ " : "  ";
                var aheadDisplay = result.Ahead > 0 ? result.Ahead.ToString() : "-";
                var behindDisplay = result.Behind > 0 ? result.Behind.ToString() : "-";

                var statusColor = result.Status switch
                {
                    "✓ Synced" => ConsoleColor.Green,
                    "⬆ Ahead" => ConsoleColor.Cyan,
                    "⬇ Behind" => ConsoleColor.Yellow,
                    "⬍ Diverged" => ConsoleColor.Red,
                    _ => ConsoleColor.Yellow
                };

                Console.Write($"{marker}{result.Branch,-33} ");
                Console.ForegroundColor = statusColor;
                Console.Write($"{result.Status,-20}");
                Console.ResetColor();
                Console.WriteLine($"{aheadDisplay,10} {behindDisplay,10}");
            }
        }
    }

    static void FormatJsonOutput(List<BranchStatus> results)
    {
        var output = new
        {
            timestamp = DateTime.UtcNow.ToString("O"),
            results = results.Select(r => new
            {
                r.Repository,
                r.Branch,
                r.Remote,
                r.Status,
                r.Ahead,
                r.Behind,
                r.IsDefault,
                r.TrackingOk
            })
        };

        var options = new JsonSerializerOptions { WriteIndented = true };
        Console.WriteLine(JsonSerializer.Serialize(output, options));
    }

    static void FormatCsvOutput(List<BranchStatus> results)
    {
        Console.WriteLine("Repository,Branch,Remote,Status,Ahead,Behind,IsDefault,Tracking");

        foreach (var result in results)
        {
            Console.WriteLine($"{result.Repository},{result.Branch},{result.Remote},{result.Status}," +
                              $"{result.Ahead},{result.Behind},{result.IsDefault},{result.TrackingOk}");
        }
    }

    static void PrintSummary(List<BranchStatus> results)
    {
        if (results.Count == 0)
            return;

        var synced = results.Count(r => r.Ahead == 0 && r.Behind == 0);
        var ahead = results.Count(r => r.Ahead > 0);
        var behind = results.Count(r => r.Behind > 0);
        var diverged = results.Count(r => r.Ahead > 0 && r.Behind > 0);
        var untracked = results.Count(r => !r.TrackingOk);

        Console.WriteLine(new string('=', 100));
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine("Summary:");
        Console.ResetColor();
        Console.WriteLine($"  Total Branches:    {results.Count}");
        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine($"  ✓ Synced:          {synced}");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Cyan;
        Console.WriteLine($"  ⬆ Ahead Only:      {ahead}");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine($"  ⬇ Behind Only:     {behind}");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Red;
        Console.WriteLine($"  ⬍ Diverged:        {diverged}");
        Console.ResetColor();
        Console.ForegroundColor = ConsoleColor.Yellow;
        Console.WriteLine($"  ⚠ Untracked:       {untracked}");
        Console.ResetColor();
    }

    static List<(string Name, string Path)> ParseSubmodules(string gitmodulesPath)
    {
        var submodules = new List<(string Name, string Path)>();

        if (!File.Exists(gitmodulesPath))
            return submodules;

        var content = File.ReadAllText(gitmodulesPath);
        var currentModule = "";
        var currentPath = "";

        foreach (var line in content.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None))
        {
            var trimmed = line.Trim();

            if (trimmed.StartsWith("[submodule"))
            {
                var match = Regex.Match(trimmed, @"\[submodule ""([^""]+)""\]");
                if (match.Success)
                    currentModule = match.Groups[1].Value;
            }
            else if (trimmed.StartsWith("path"))
            {
                var match = Regex.Match(trimmed, @"path\s*=\s*(.+)");
                if (match.Success)
                {
                    currentPath = match.Groups[1].Value;
                    submodules.Add((currentModule, currentPath));
                }
            }
        }

        return submodules;
    }

    enum OutputFormat { Table, Json, Csv }

    class Options
    {
        public string Path { get; set; }
        public string RemoteName { get; set; }
        public string BranchPattern { get; set; }
        public bool AllSubmodules { get; set; }
        public string GitmodulesPath { get; set; }
        public bool Verbose { get; set; }
        public OutputFormat Format { get; set; }
    }

    class BranchStatus
    {
        public string Repository { get; set; }
        public string Branch { get; set; }
        public string Remote { get; set; }
        public string RemoteBranch { get; set; }
        public int Ahead { get; set; }
        public int Behind { get; set; }
        public string Status { get; set; }
        public string LocalHash { get; set; }
        public string RemoteHash { get; set; }
        public bool IsDefault { get; set; }
        public bool TrackingOk { get; set; }
    }
}
