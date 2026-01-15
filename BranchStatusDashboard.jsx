import React, { useState, useEffect } from 'react';

export default function BranchStatusDashboard() {
  const [branches, setBranches] = useState([]);
  const [loading, setLoading] = useState(false);
  const [filter, setFilter] = useState('all');
  const [selectedRepo, setSelectedRepo] = useState('all');
  const [remoteName, setRemoteName] = useState('upstream');

  useEffect(() => {
    // In a real app, this would call the actual script
    // For now, we'll use sample data
    loadSampleData();
  }, []);

  const loadSampleData = () => {
    setBranches([
      {
        repo: 'BlockChainExample',
        branch: 'main',
        status: 'synced',
        ahead: 0,
        behind: 0,
        isDefault: true,
        tracking: true,
      },
      {
        repo: 'BlockChainExample',
        branch: 'feature/improvements',
        status: 'ahead',
        ahead: 3,
        behind: 0,
        isDefault: false,
        tracking: true,
      },
      {
        repo: 'MSBuild.Sdk.SqlProj',
        branch: 'develop',
        status: 'behind',
        ahead: 0,
        behind: 5,
        isDefault: true,
        tracking: true,
      },
      {
        repo: 'MSBuild.Sdk.SqlProj',
        branch: 'feature/sql-support',
        status: 'diverged',
        ahead: 2,
        behind: 3,
        isDefault: false,
        tracking: true,
      },
      {
        repo: 'cline',
        branch: 'main',
        status: 'synced',
        ahead: 0,
        behind: 0,
        isDefault: true,
        tracking: true,
      },
      {
        repo: 'vivado-library',
        branch: 'master',
        status: 'behind',
        ahead: 0,
        behind: 12,
        isDefault: true,
        tracking: true,
      },
      {
        repo: 'DOOM',
        branch: 'main',
        status: 'ahead',
        ahead: 7,
        behind: 0,
        isDefault: true,
        tracking: true,
      },
    ]);
  };

  const getRepos = () => {
    const repos = new Set(branches.map((b) => b.repo));
    return Array.from(repos).sort();
  };

  const getFilteredBranches = () => {
    return branches.filter((b) => {
      const repoMatch = selectedRepo === 'all' || b.repo === selectedRepo;
      const filterMatch =
        filter === 'all' ||
        (filter === 'ahead' && b.ahead > 0) ||
        (filter === 'behind' && b.behind > 0) ||
        (filter === 'diverged' && b.ahead > 0 && b.behind > 0) ||
        (filter === 'synced' && b.ahead === 0 && b.behind === 0) ||
        (filter === 'untracked' && !b.tracking);
      return repoMatch && filterMatch;
    });
  };

  const getSummary = () => {
    return {
      total: branches.length,
      synced: branches.filter((b) => b.ahead === 0 && b.behind === 0).length,
      ahead: branches.filter((b) => b.ahead > 0 && b.behind === 0).length,
      behind: branches.filter((b) => b.ahead === 0 && b.behind > 0).length,
      diverged: branches.filter((b) => b.ahead > 0 && b.behind > 0).length,
      untracked: branches.filter((b) => !b.tracking).length,
    };
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'synced':
        return 'bg-green-100 text-green-700 border-green-300';
      case 'ahead':
        return 'bg-blue-100 text-blue-700 border-blue-300';
      case 'behind':
        return 'bg-yellow-100 text-yellow-700 border-yellow-300';
      case 'diverged':
        return 'bg-red-100 text-red-700 border-red-300';
      default:
        return 'bg-gray-100 text-gray-700 border-gray-300';
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'synced':
        return '✓';
      case 'ahead':
        return '⬆';
      case 'behind':
        return '⬇';
      case 'diverged':
        return '⬍';
      default:
        return '?';
    }
  };

  const getStatusLabel = (status) => {
    switch (status) {
      case 'synced':
        return 'Synced';
      case 'ahead':
        return 'Ahead';
      case 'behind':
        return 'Behind';
      case 'diverged':
        return 'Diverged';
      default:
        return 'Unknown';
    }
  };

  const filtered = getFilteredBranches();
  const summary = getSummary();
  const repos = getRepos();

  return (
    <div className="min-h-screen" style={{ background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 100%)' }}>
      {/* Header */}
      <div className="border-b border-gray-700 bg-black bg-opacity-40 backdrop-blur sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-6 py-6">
          <h1 className="text-4xl font-bold text-white mb-2">Git Branch Status</h1>
          <p className="text-gray-400">Monitor ahead/behind status across repositories</p>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="max-w-7xl mx-auto px-6 py-8">
        <div className="grid grid-cols-2 md:grid-cols-6 gap-4 mb-8">
          <div className="bg-gradient-to-br from-gray-700 to-gray-800 rounded-lg p-4 border border-gray-600">
            <div className="text-gray-400 text-sm font-medium">Total</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.total}</div>
          </div>
          <div className="bg-gradient-to-br from-green-700 to-green-800 rounded-lg p-4 border border-green-600">
            <div className="text-green-200 text-sm font-medium">✓ Synced</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.synced}</div>
          </div>
          <div className="bg-gradient-to-br from-blue-700 to-blue-800 rounded-lg p-4 border border-blue-600">
            <div className="text-blue-200 text-sm font-medium">⬆ Ahead</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.ahead}</div>
          </div>
          <div className="bg-gradient-to-br from-yellow-700 to-yellow-800 rounded-lg p-4 border border-yellow-600">
            <div className="text-yellow-200 text-sm font-medium">⬇ Behind</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.behind}</div>
          </div>
          <div className="bg-gradient-to-br from-red-700 to-red-800 rounded-lg p-4 border border-red-600">
            <div className="text-red-200 text-sm font-medium">⬍ Diverged</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.diverged}</div>
          </div>
          <div className="bg-gradient-to-br from-gray-600 to-gray-700 rounded-lg p-4 border border-gray-500">
            <div className="text-gray-300 text-sm font-medium">⚠ Untracked</div>
            <div className="text-3xl font-bold text-white mt-2">{summary.untracked}</div>
          </div>
        </div>

        {/* Filters */}
        <div className="bg-gray-800 bg-opacity-50 backdrop-blur rounded-lg p-6 border border-gray-700 mb-8">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-3">Repository</label>
              <select
                value={selectedRepo}
                onChange={(e) => setSelectedRepo(e.target.value)}
                className="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:border-blue-500"
              >
                <option value="all">All Repositories</option>
                {repos.map((repo) => (
                  <option key={repo} value={repo}>
                    {repo}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-3">Status Filter</label>
              <select
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                className="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:border-blue-500"
              >
                <option value="all">All Statuses</option>
                <option value="synced">Synced</option>
                <option value="ahead">Ahead</option>
                <option value="behind">Behind</option>
                <option value="diverged">Diverged</option>
                <option value="untracked">Untracked</option>
              </select>
            </div>
          </div>
        </div>

        {/* Branches List */}
        <div className="space-y-6">
          {repos
            .filter((repo) => selectedRepo === 'all' || repo === selectedRepo)
            .map((repo) => {
              const repoBranches = filtered.filter((b) => b.repo === repo);
              if (repoBranches.length === 0) return null;

              return (
                <div key={repo} className="space-y-4">
                  <h2 className="text-2xl font-bold text-white border-l-4 border-blue-500 pl-4">{repo}</h2>

                  <div className="grid gap-4">
                    {repoBranches.map((branch, idx) => (
                      <div
                        key={`${repo}-${branch.branch}-${idx}`}
                        className="bg-gray-800 bg-opacity-50 backdrop-blur border border-gray-700 rounded-lg p-4 hover:border-gray-500 transition"
                      >
                        <div className="flex items-center justify-between gap-4 flex-wrap">
                          <div className="flex items-center gap-3">
                            {branch.isDefault && <span className="text-xl">◆</span>}
                            <div>
                              <h3 className="text-lg font-semibold text-white">{branch.branch}</h3>
                              {!branch.tracking && (
                                <p className="text-sm text-yellow-400">⚠ No upstream tracking</p>
                              )}
                            </div>
                          </div>

                          <div className="flex items-center gap-4">
                            <div className={`px-4 py-2 rounded-lg border font-medium ${getStatusColor(branch.status)}`}>
                              <span className="mr-2">{getStatusIcon(branch.status)}</span>
                              {getStatusLabel(branch.status)}
                            </div>

                            <div className="flex gap-6">
                              {branch.ahead > 0 && (
                                <div className="text-center">
                                  <div className="text-2xl font-bold text-blue-400">{branch.ahead}</div>
                                  <div className="text-xs text-gray-400 mt-1">Ahead</div>
                                </div>
                              )}
                              {branch.behind > 0 && (
                                <div className="text-center">
                                  <div className="text-2xl font-bold text-yellow-400">{branch.behind}</div>
                                  <div className="text-xs text-gray-400 mt-1">Behind</div>
                                </div>
                              )}
                              {branch.ahead === 0 && branch.behind === 0 && (
                                <div className="text-center">
                                  <div className="text-2xl font-bold text-green-400">—</div>
                                  <div className="text-xs text-gray-400 mt-1">Synced</div>
                                </div>
                              )}
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}

          {filtered.length === 0 && (
            <div className="bg-gray-800 bg-opacity-50 backdrop-blur rounded-lg p-12 border border-gray-700 text-center">
              <p className="text-gray-400 text-lg">No branches match the selected filters</p>
            </div>
          )}
        </div>

        {/* Footer Info */}
        <div className="mt-12 text-center text-gray-500 text-sm">
          <p>Monitoring against remote: <span className="text-gray-300 font-mono">{remoteName}</span></p>
          <p>Last updated: {new Date().toLocaleString()}</p>
        </div>
      </div>
    </div>
  );
}
