$ErrorActionPreference = 'Stop'
$regpath = '{{registry_scope}}:\Software'
$identifier = 'dev.aninsomniacy.rayburst'
# Rayburst checks the loaded executable path when opening its Default apps page.
$executable = '{{scoop_dir}}\rayburst.exe'
$icon = '"{0}",0' -f $executable
$command = '"{0}" "%1"' -f $executable

foreach ($association in @('torrent', 'magnet', 'ed2k', 'thunder', 'rayburst')) {
    $progid = "$identifier.$association"
    $class = "$regpath\Classes\$progid"
    New-Item -Path "$class\DefaultIcon" -Force | Out-Null
    New-Item -Path "$class\shell\open\command" -Force | Out-Null
    Set-Item -Path $class -Value "Rayburst $association"
    Set-Item -Path "$class\DefaultIcon" -Value $icon
    Set-Item -Path "$class\shell\open\command" -Value $command
    if ($association -ne 'torrent') {
        New-ItemProperty -Path $class -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    }
}

# Advertise handlers without changing the user's default applications.
$capabilities = "$regpath\$identifier\Capabilities"
New-Item -Path "$capabilities\FileAssociations" -Force | Out-Null
New-Item -Path "$capabilities\URLAssociations" -Force | Out-Null
New-ItemProperty -Path $capabilities -Name ApplicationName -Value 'Rayburst' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $capabilities -Name ApplicationDescription -Value 'Download files and media with Rayburst' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $capabilities -Name ApplicationIcon -Value $icon -PropertyType String -Force | Out-Null
New-ItemProperty -Path "$capabilities\FileAssociations" -Name '.torrent' -Value "$identifier.torrent" -PropertyType String -Force | Out-Null
foreach ($scheme in @('magnet', 'ed2k', 'thunder', 'rayburst')) {
    New-ItemProperty -Path "$capabilities\URLAssociations" -Name $scheme -Value "$identifier.$scheme" -PropertyType String -Force | Out-Null
}

New-Item -Path "$regpath\RegisteredApplications" -Force | Out-Null
New-ItemProperty -Path "$regpath\RegisteredApplications" -Name $identifier -Value "Software\$identifier\Capabilities" -PropertyType String -Force | Out-Null
New-Item -Path "$regpath\Classes\.torrent\OpenWithProgids" -Force | Out-Null
New-ItemProperty -Path "$regpath\Classes\.torrent\OpenWithProgids" -Name "$identifier.torrent" -Value '' -PropertyType String -Force | Out-Null
