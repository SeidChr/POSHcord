$script:id = 0

class WebSocketData {
    [Net.WebSockets.ClientWebSocket]
    $WebSocket

    [System.ArraySegment[byte]]
    $Buffer

    [Threading.CancellationTokenSource]
    [Alias('cts')]
    $CancellationTokenSource
}

function Write-Log {
    $script:id++; Write-Host "$script:id : $($args[0])" 
}

function Test-Open {
    param(
        [Parameter(ValueFromPipeline)]
        [WebSocketData]
        $WebSocketData
    )

    return $WebSocketData.WebSocket.State -eq [Net.WebSockets.WebSocketState]::Open
}

function Receive-Message {
    param(
        [Parameter(ValueFromPipeline)]
        [WebSocketData]
        [Alias("wsd")]
        $WebSocketData
    )

    $body = ''
    do {
        $receiveResult = $WebSocketData.WebSocket.ReceiveAsync(
            $WebSocketData.Buffer,
            $WebSocketData.CancellationTokenSource.Token
        ).GetAwaiter().GetResult()

        $body += [Text.Encoding]::UTF8.GetString($WebSocketData.Buffer, 0, $receiveResult.Count)
        Write-Log "EndOfMessage $($receiveResult.EndOfMessage) WS-State: $($WebSocketData.WebSocket.State)"
        Write-Log "Received $($receiveResult.Count) Bytes: $body"
    } until (
        !($ws | Test-Open) -or $receiveResult.EndOfMessage
    )

    return $body | ConvertFrom-Json -Depth 100
}

function Send-Message { 
    param(
        [Parameter(ValueFromPipeline)]
        [WebSocketData]
        [Alias("wsd")]
        $WebSocketData,

        $Message
    )

    $text = $Message | ConvertTo-Json -Depth 100 -Compress

    if ($WebSocketData | Test-Open) {
        [ArraySegment[byte]] $data = [Text.Encoding]::UTF8.GetBytes($text)
        $wsd.WebSocket.SendAsync(
            $data,
            [System.Net.WebSockets.WebSocketMessageType]::Binary,
            $true,
            $WebSocketData.CancellationTokenSource.Token
        ).GetAwaiter().GetResult() | Out-Null
        Write-Log "Sent message: $text"
    } else {
        Write-Log "Cannot send message. Socket not open."
    }
}

function Connect-WebSocket {
    [OutputType([WebSocketData])]
    param(
        [string]
        $Url,

        [System.Threading.CancellationTokenSource]
        [Alias('cts')]
        $CancellationTokenSource = [Threading.CancellationTokenSource]::new(),

        [int] $BufferSizeBytes = 4906
    )

    $result = [WebSocketData]::new()
    $result.WebSocket = [Net.WebSockets.ClientWebSocket]::new()
    $result.Buffer = [Net.WebSockets.WebSocket]::CreateClientBuffer($BufferSizeBytes, $BufferSizeBytes)
    $result.CancellationTokenSource = $CancellationTokenSource

    $result.WebSocket.ConnectAsync($Url, $result.CancellationTokenSource.Token).GetAwaiter().GetResult() | Out-Null
    Write-Log "Connected WebSocket"

    return $result
}

function Start-WebSocketReceiver {
    param(
        [Parameter(ValueFromPipeline)]
        [WebSocketData]
        [Alias("wsd")]
        $WebSocketData
    )

    Start-ThreadJob {
        # load the current
        . $using:PSCommandPath
        $wsd = $using:WebSocketData
        # $si = $using:SourceIdentifier

        while ($wsd | Test-Open) {
            $body = $wsd | Receive-Message
            if ($body) {
                # New-Event -SourceIdentifier $si -Sender $wsd -MessageData $body
                $body
            }
        }
    }
}