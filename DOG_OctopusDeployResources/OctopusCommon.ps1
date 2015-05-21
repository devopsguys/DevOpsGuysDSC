function Get-TentacleServiceName
{
    param (
        [string] $TentacleName = 'Tentacle'
    )

    $svcName = 'OctopusDeploy Tentacle'
    if ($TentacleName -ne 'Tentacle')
    {
        $svcName += ": $TentacleName"
    }

    return $svcName
}
