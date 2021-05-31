. .\lib\WebSocket.lib.ps1
. .\lib\Discord.lib.ps1

$token = (Get-Content .\token.txt -Raw).Trim()

function Resolve-Error ($ErrorRecord = $Error[0]) {
    $ErrorRecord | Format-List * -Force
    $ErrorRecord.InvocationInfo | Format-List *
    $Exception = $ErrorRecord.Exception
    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException)) {
        "$i" * 80
        $Exception | Format-List * -Force
    }
}

try {
    $state = New-DiscordState -Token $token
    $url = Get-DiscordGatewayUrl

    Write-Log $url
    $wsd = Connect-WebSocket $url
    $messageReceiverJob = Start-WebSocketReceiver -WebSocketData $wsd

    while ($true) {
        $messages = $messageReceiverJob | Receive-Job -ErrorAction Continue
        if ($messages) {
            Write-Host "Messages:" ($messages | ConvertTo-Json -Depth 100 -Compress)

            $messages | ForEach-Object {
                $state | Receive-DiscordEventPayload -EventPayload ($_ | ConvertTo-DiscordEventPayload)
            }
            "Post-Received:"
            $state | ConvertTo-Json -Depth 100
        }

        $state | Get-QueedMessages | ForEach-Object { $wsd | Send-Message -Message $_ }

        # some time to breathe
        Start-Sleep -Seconds 1
    }
} catch {
    Write-Host "Error:" $_.Exception.Message
    Resolve-Error
} finally {
    Write-Host "Script finished. Cleaning up."
    $wsd.CancellationTokenSource.Cancel()
    $messageReceiverJob | Remove-Job -Force
}
