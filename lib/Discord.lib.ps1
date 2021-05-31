# https://discord.com/developers/docs/topics/gateway

using namespace System.Collections.Specialized
using namespace System.Collections.Generic

class DiscordState {
    # milliseconds
    [int] $HeartbeatInterval

    [int] $TimeToHeartbeat

    [Queue[OrderedDictionary]]
    $SendQueue = [Queue[OrderedDictionary]]::new()

    [string] $Token

    [int] $SequenceNumber

    [string] $SessionId
    [string] $UserId
    [string] $ApplicationId
}

function ConvertTo-DiscordEventPayload {
    [OutputType([OrderedDictionary])]
    param([Parameter(ValueFromPipeline)] $Source)
    return New-DiscordEventPayload -OpCode $Source.op -SequenceNumber $Source.s -EventName $Source.t -Data $Source.d
}

function New-DiscordEventPayload {
    [OutputType([OrderedDictionary])]
    param(
        [Alias('op')]
        [int]
        $OpCode,

        [Alias('s')]
        $SequenceNumber = $null,

        [Alias('t')]
        $EventName = $null,

        [Alias('d')]
        $Data
    )

    $result = [ordered]@{
        op = $OpCode
    }

    if ($Data) {
        $result['d'] = $Data
    }
    if ($SequenceNumber) {
        $result['s'] = $SequenceNumber
    }
    if ($EventName) {
        $result['t'] = $EventName
    }


    return $result
}

function Get-DiscordGatewayUrl {
    $discordApiBaseUrl = "https://discord.com/api"
    $discordGatewayBaseUrl = (Invoke-RestMethod "$discordApiBaseUrl/gateway").url
    return "$discordGatewayBaseUrl/?v=6&encoding=json"
}

function New-DiscordState {
    [OutputType([DiscordState])]
    param([Parameter(Mandatory)] [string] $Token)
    $Result = [DiscordState]::new()
    $Result.Token = $Token
    return $Result
}

function Set-SequenceNumber {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State,

        [OrderedDictionary]
        $EventPayload
    )
    # Write-Host ($State | ConvertTo-Json -Depth 100)
    $State.SequenceNumber = $EventPayload.s
}

function Set-OpCode_00_Ready {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State,

        [OrderedDictionary]
        $EventPayload
    )

    # Write-Host "Received Ready (Op 0): $($EventPayload | ConvertTo-Json -Depth 100 -Compress)"
    Write-Host "Received Ready (Op 0)"
    
    $State.SessionId = $EventPayload.d.session_id
    $State.ApplicationId = $EventPayload.d.application.id
    $State.UserId = $EventPayload.d.user.id

    Write-Host "SessionID: $($State.SessionId)"
    Write-Host "ApplicationID: $($State.ApplicationId)"
    Write-Host "UserID: $($State.UserId)"

    # this makes discord wanting to close the connection
    # $State | Send-DiscordEventPayload -EventPayload (New-DiscordEventPayload -OpCode 11)
}

function Set-OpCode_10_Hello {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State,

        [OrderedDictionary]
        $EventPayload
    )

    Write-Host "Received Hello (Op 10): $($EventPayload | ConvertTo-Json -Depth 100 -Compress)"
    $State.HeartbeatInterval = $EventPayload.d.heartbeat_interval
    # https://discord.com/developers/docs/topics/gateway#identifying
    # $answerPayload = (New-DiscordEventPayload -OpCode 11), (New-DiscordEventPayload -OpCode 2 -Data @{ 
    $answerPayload = (New-DiscordEventPayload -OpCode 2 -Data @{ 
        token               = $State.Token
        # intents             = 0b111 -shl 12 # https://discord.com/developers/docs/topics/gateway#gateway-intents
        intents             = 513 # https://discord.com/developers/docs/topics/gateway#gateway-intents
        compress            = $false
        guild_subscriptions = $false
        properties          = [ordered]@{
            '$os'      = "windows"
            '$browser' = "POSH"
            '$device'  = "POSH"
        }
    })

    $answerPayload | ForEach-Object { $State | Send-DiscordEventPayload -EventPayload:$_ }
}

function Send-DiscordEventPayload {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State,

        [OrderedDictionary]
        $EventPayload
    )

    if ($State.SequenceNumber) {
        $State.SequenceNumber++

        $EventPayload.s = $State.SequenceNumber
    }

    $State.SendQueue.Enqueue($EventPayload)
}

function Receive-DiscordEventPayload {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State,

        [OrderedDictionary]
        $EventPayload
    )

    $State | Set-SequenceNumber -EventPayload $EventPayload

    switch ($EventPayload.op) {
        00 { $State | Set-OpCode_00_Ready -EventPayload $EventPayload }
        10 { $State | Set-OpCode_10_Hello -EventPayload $EventPayload }
        Default { Write-Host "Received OpCode $($EventPayload.op) not found." }
    }

    Write-Host ($State | ConvertTo-Json -Compress)
}

function Get-QueedMessages {
    param(
        [Parameter(ValueFromPipeline)]
        [DiscordState]
        $State
    )

    if ($state.SendQueue.Count -gt 0) {
        $sendMessage = $null
        while ($state.SendQueue.TryDequeue([ref] $sendMessage)) {
            $sendMessage
            $sendMessage = $null # make it a new reference
        }
    }
}