function Invoke-AwsApi
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]
        $Command
    )

    $_command = $Command
    
    $_base    = 2
    $_attempt = 0

    while ($true)
    {
        $_attempt++
        try {
            return & $_command
        }
        catch {
            if ($_.Exception.Message -like '*rate exceeded*') {
                $_cool_down = [Math]::Pow($_base, $_attempt - 1)
                Write-Warning "Hit throttling on attempt $($_attempt). Cooling down for $($_cool_down) second(s)."
                Start-Sleep -Seconds $_cool_down
            }
        }
    }
}
