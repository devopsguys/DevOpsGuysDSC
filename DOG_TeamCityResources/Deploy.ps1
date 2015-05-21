param (
    [string] $Path
)

end
{
    Get-ChildItem -Path $PSScriptRoot\* -Recurse -File -Exclude '*.zip', '*.Tests.ps1', 'Deploy.ps1' |
    ForEach-Object {
        $file = $_

        $relativePath = Get-RelativePath -Path $file.FullName -RelativeTo $PSScriptRoot
        $targetPath = Join-Path $Path $relativePath
        $targetFolder = Split-Path $targetPath -Parent

        if (-not (Test-Path -LiteralPath $targetFolder -PathType Container))
        {
            $null = New-Item -Path $targetFolder -ItemType Directory
        }

        Copy-Item -LiteralPath $file.FullName -Destination $targetFolder\
    }
}

begin
{
    function Get-RelativePath
    {
        param ( [string] $Path, [string] $RelativeTo )
        return $Path -replace "^$([regex]::Escape($RelativeTo))\\?"
    }
}
