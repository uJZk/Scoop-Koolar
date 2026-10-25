$ErrorActionPreference = 'Stop'
$regpath = '{{registry_scope}}:\Software'
$identifier = 'dev.aninsomniacy.rayburst'
$executable = '{{scoop_dir}}\rayburst.exe'
$command = '"{0}" "%1"' -f $executable

foreach ($association in @('torrent', 'magnet', 'ed2k', 'thunder', 'rayburst')) {
    $class = "$regpath\Classes\$identifier.$association"
    $registeredCommand = Get-Item -Path "$class\shell\open\command" -ErrorAction SilentlyContinue
    if ($registeredCommand -and $registeredCommand.GetValue('') -eq $command) {
        Remove-Item -Path $class -Recurse -Force
    }
}

# The application also registers its private scheme while running.
$class = "$regpath\Classes\rayburst"
$registeredCommand = Get-Item -Path "$class\shell\open\command" -ErrorAction SilentlyContinue
if ($registeredCommand -and $registeredCommand.GetValue('') -eq $command) {
    Remove-Item -Path $class -Recurse -Force
}

# Leave registrations belonging to another Rayburst installation intact.
$capabilities = "$regpath\$identifier\Capabilities"
$registeredIcon = Get-ItemProperty -Path $capabilities -Name ApplicationIcon -ErrorAction SilentlyContinue
if ($registeredIcon -and $registeredIcon.ApplicationIcon -eq ('"{0}",0' -f $executable)) {
    Remove-ItemProperty -Path "$regpath\RegisteredApplications" -Name $identifier -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$regpath\Classes\.torrent\OpenWithProgids" -Name "$identifier.torrent" -ErrorAction SilentlyContinue
    Remove-Item -Path $capabilities -Recurse -Force
}
