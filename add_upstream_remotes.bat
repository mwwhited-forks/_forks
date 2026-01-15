REM @echo off
setlocal EnableDelayedExpansion

if not exist .gitmodules (
    echo ERROR: .gitmodules not found. Run this from the repo root.
    exit /b 1
)

echo Processing submodules...

REM Get each submodule path
for /f "tokens=2" %%P in ('
    git config --file .gitmodules --get-regexp submodule^^..*^^.path
') do (

    set "SUBMODULE_PATH=%%P"
    set "UPSTREAM_URL="

    REM Find matching upstream entry by path
    for /f "tokens=2" %%U in ('
        git config --file .gitmodules --get-regexp submodule^^..*^^.upstream
    ') do (
        set "UPSTREAM_URL=%%U"
    )

    if not defined UPSTREAM_URL (
        echo.
        echo Submodule %%P has no upstream defined — skipping
    ) else (
        echo.
        echo Submodule path: %%P
        echo Upstream: !UPSTREAM_URL!

        pushd "%%P" >nul 2>&1
        if errorlevel 1 (
            echo WARNING: Cannot enter directory
        ) else (
            git remote get-url upstream >nul 2>&1
            if errorlevel 1 (
                git remote add upstream "!UPSTREAM_URL!"
                echo Added upstream remote
            ) else (
                echo Upstream remote already exists
            )
            popd
        )
    )
)

echo.
echo Done.
endlocal
