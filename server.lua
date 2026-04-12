local currentVersion = 'v1.0.0'

local function fetchLatestVersion(callback)
    PerformHttpRequest('https://api.github.com/repos/RealisticScripts/rs-artifact-updates/releases/latest', function(statusCode, response)
        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.tag_name then
                callback(data.tag_name)
            else
                print('[rs-artifact-updates] Failed to fetch the latest version')
            end
        else
            print(('[rs-artifact-updates] HTTP request failed with status code: %s'):format(statusCode))
        end
    end, 'GET')
end

local function checkForUpdates()
    fetchLatestVersion(function(latestVersion)
        if currentVersion ~= latestVersion then
            print('[rs-artifact-updates] A new version of the script is available!')
            print(('[rs-artifact-updates] Current version: %s'):format(currentVersion))
            print(('[rs-artifact-updates] Latest version: %s'):format(latestVersion))
            print('[rs-artifact-updates] Please update the script from: https://github.com/RealisticScripts/rs-artifact-updates')
        else
            print('[rs-artifact-updates] Your script is up to date!')
        end
    end)
end

local RESOURCE_NAME = 'rs-artifact-updates'
local ARTIFACTS_URL = 'https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/'

local lastSeenListed
local lastSeenRecommended
local lastNotifiedAvailableBuild

local function getConfigValue(key, fallback)
    if type(Config) ~= 'table' or Config[key] == nil then
        return fallback
    end

    return Config[key]
end

local function logConsole(message)
    print(('[%s] %s'):format(RESOURCE_NAME, message))
end

local function logDebug(message)
    if getConfigValue('Debug', false) then
        logConsole(('[DEBUG] %s'):format(message))
    end
end

local function normalizeIntervalMinutes()
    local intervalMinutes = tonumber(getConfigValue('CheckIntervalMinutes', 60)) or 60

    if intervalMinutes < 1 then
        intervalMinutes = 1
    end

    intervalMinutes = math.floor(intervalMinutes)
    logDebug(('Normalized check interval to %d minute(s).'):format(intervalMinutes))

    return intervalMinutes
end

local function sendDiscordLog(title, description)
    local webhook = getConfigValue('DiscordWebhook', '')

    if type(webhook) ~= 'string' or webhook == '' then
        logDebug('Discord webhook is empty. Discord log skipped.')
        return
    end

    local payload = {
        username = RESOURCE_NAME,
        embeds = {
            {
                title = title,
                description = description,
                color = 16760576,
                footer = {
                    text = RESOURCE_NAME
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }

    PerformHttpRequest(webhook, function(statusCode)
        if statusCode < 200 or statusCode >= 300 then
            logConsole(('Discord logging failed with status code: %s'):format(tostring(statusCode)))
            return
        end

        logDebug(('Discord log sent successfully: %s'):format(title))
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function parseBuildFromVersionString(version)
    if type(version) ~= 'string' or version == '' then
        return nil
    end

    local patterns = {
        'windows:%w+/(%d+)',
        'linux:%w+/(%d+)',
        'b(%d+)/%a+',
        'build[%s:_-]*(%d+)',
        'v%d+%.%d+%.%d+%.(%d+)',
        '/(%d+)$'
    }

    for _, pattern in ipairs(patterns) do
        local build = version:match(pattern)
        if build then
            return tonumber(build)
        end
    end

    return nil
end

local function getCurrentArtifactBuild()
    local rawVersion = GetConvar('version', '')
    local currentBuild = parseBuildFromVersionString(rawVersion)

    logDebug(('Raw version convar: %s'):format(rawVersion ~= '' and rawVersion or 'not set'))
    logDebug(('Parsed current artifact build: %s'):format(currentBuild and tostring(currentBuild) or 'nil'))

    return currentBuild, rawVersion
end

local function parseLatestRecommended(html)
    if type(html) ~= 'string' or html == '' then
        return nil
    end

    return tonumber(html:match('LATEST%s+RECOMMENDED%s*%((%d+)%)'))
end

local function parseLatestOptional(html)
    if type(html) ~= 'string' or html == '' then
        return nil
    end

    return tonumber(html:match('LATEST%s+OPTIONAL%s*%((%d+)%)'))
end

local function parseLatestListed(html)
    if type(html) ~= 'string' or html == '' then
        return nil
    end

    local latestBuild
    local patterns = {
        '(%d+)%-%x+/server%.7z',
        '(%d+)%-%w+/server%.7z',
        '(%d+)%-%x+/fx%.tar%.xz',
        '(%d+)%-%w+/fx%.tar%.xz'
    }

    for _, pattern in ipairs(patterns) do
        for build in html:gmatch(pattern) do
            build = tonumber(build)

            if build and (not latestBuild or build > latestBuild) then
                latestBuild = build
            end
        end

        if latestBuild then
            break
        end
    end

    return latestBuild
end

local function formatArtifactSummary(currentBuild, latestListed, latestRecommended, latestOptional)
    local parts = {
        ('Current artifact build: %s'):format(currentBuild and tostring(currentBuild) or 'unknown'),
        ('Latest listed: %s'):format(latestListed and tostring(latestListed) or 'unknown'),
        ('Latest recommended: %s'):format(latestRecommended and tostring(latestRecommended) or 'unknown'),
        ('Latest optional: %s'):format(latestOptional and tostring(latestOptional) or 'unknown')
    }

    return table.concat(parts, ' | ')
end

local function logArtifactStatus(currentBuild, latestListed, latestRecommended, latestOptional)
    logConsole(formatArtifactSummary(currentBuild, latestListed, latestRecommended, latestOptional))
end

local function handleArtifactCheck(isStartup)
    local currentBuild, rawVersion = getCurrentArtifactBuild()

    if not currentBuild then
        local message = ('Unable to detect the current artifact build from version convar: %s'):format(rawVersion ~= '' and rawVersion or 'not set')
        logConsole(message)
        sendDiscordLog('Artifact build detection failed', message)
        return
    end

    logDebug(('Checking artifacts URL: %s'):format(ARTIFACTS_URL))

    PerformHttpRequest(ARTIFACTS_URL, function(statusCode, responseBody)
        logDebug(('Artifacts request status code: %s'):format(tostring(statusCode)))

        if statusCode ~= 200 or type(responseBody) ~= 'string' or responseBody == '' then
            local message = ('Failed to check FiveM artifacts. HTTP status code: %s'):format(tostring(statusCode))
            logConsole(message)
            sendDiscordLog('Artifact check failed', message)
            return
        end

        local latestListed = parseLatestListed(responseBody)
        local latestRecommended = parseLatestRecommended(responseBody)
        local latestOptional = parseLatestOptional(responseBody)

        logDebug(('Parsed latest listed artifact: %s'):format(latestListed and tostring(latestListed) or 'nil'))
        logDebug(('Parsed latest recommended artifact: %s'):format(latestRecommended and tostring(latestRecommended) or 'nil'))
        logDebug(('Parsed latest optional artifact: %s'):format(latestOptional and tostring(latestOptional) or 'nil'))

        if not latestListed then
            local message = 'Failed to parse the latest listed artifact from the official FiveM artifacts page.'
            logConsole(message)
            sendDiscordLog('Artifact parsing failed', message)
            return
        end

        logArtifactStatus(currentBuild, latestListed, latestRecommended, latestOptional)

        if lastSeenListed and latestListed > lastSeenListed then
            local releaseMessage = ('A new listed FiveM artifact has been published. Previous: %d | New: %d'):format(lastSeenListed, latestListed)
            logConsole(releaseMessage)
            sendDiscordLog('New listed FiveM artifact detected', releaseMessage)
        end

        if latestRecommended and lastSeenRecommended and latestRecommended > lastSeenRecommended then
            local recommendedMessage = ('A new recommended FiveM artifact has been published. Previous: %d | New: %d'):format(lastSeenRecommended, latestRecommended)
            logConsole(recommendedMessage)
            sendDiscordLog('New recommended FiveM artifact detected', recommendedMessage)
        end

        if currentBuild < latestListed then
            local updateMessage = ('A new FiveM artifact is available. Current: %d | Latest listed: %d'):format(currentBuild, latestListed)
            logConsole(updateMessage)

            if isStartup or lastNotifiedAvailableBuild ~= latestListed then
                sendDiscordLog('FiveM artifact update available', updateMessage)
                lastNotifiedAvailableBuild = latestListed
            end
        else
            local upToDateMessage = ('Your current artifact is up to date. Current: %d | Latest listed: %d'):format(currentBuild, latestListed)
            logConsole(upToDateMessage)

            if isStartup then
                sendDiscordLog('FiveM artifact status', upToDateMessage)
            end

            lastNotifiedAvailableBuild = nil
        end

        lastSeenListed = latestListed
        lastSeenRecommended = latestRecommended
    end, 'GET')
end

CreateThread(function()
    local intervalMinutes = normalizeIntervalMinutes()

    logConsole(('Resource started. Check interval: %d minute(s). Debug: %s'):format(
        intervalMinutes,
        getConfigValue('Debug', false) and 'on' or 'off'
    ))

    sendDiscordLog('Resource started', ('Check interval: %d minute(s) | Debug: %s'):format(
        intervalMinutes,
        getConfigValue('Debug', false) and 'on' or 'off'
    ))

    checkForUpdates()
    handleArtifactCheck(true)

    while true do
        Wait(intervalMinutes * 60000)
        handleArtifactCheck(false)
    end
end)
