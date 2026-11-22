#Requires -Version 7.3
param(
    [Parameter(Mandatory)]
    [ValidateSet('postgresql', 'mariadb', 'mongodb', 'neo4j')]
    [string]$Engine,
    [Parameter(Mandatory)]
    [string]$Dataset,
    [Parameter(Mandatory)]
    [string]$Database
)

$ErrorActionPreference = 'Stop'
if ($Database -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') {
    throw 'Invalid database name.'
}
$root = (Resolve-Path -LiteralPath $Dataset).Path
if (-not (Test-Path -LiteralPath (Join-Path $root 'manifest.json') -PathType Leaf)) {
    throw 'Dataset is incomplete: manifest.json is missing.'
}

function Invoke-Client([string]$Client, [string[]]$Arguments) {
    & $Client @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Client exited with code $LASTEXITCODE."
    }
}

if ($Engine -eq 'mongodb') {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'mongo') -Filter '*.ndjson') {
        if ($file.Length -gt 0) {
            $arguments = @('--db', $Database, '--collection', $file.BaseName,
                '--file', $file.FullName, '--stopOnError')
            Invoke-Client mongoimport $arguments
        }
    }
    return
}

if ($Engine -eq 'neo4j') {
    # Nazwa bazy musi stać przed --nodes/--relationships: te opcje przyjmują wiele plików
    # i nazwa na końcu zostałaby potraktowana jako plik ("Unable to find the parent of the path").
    $arguments = @('database', 'import', 'full', $Database, '--id-type=integer', '--legacy-style-quoting=false')
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'neo4j') -Filter 'node-*.csv') {
        $label = $file.BaseName.Substring(5)
        $arguments += "--nodes=${label}=$($file.FullName)"
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'neo4j') -Filter 'rel-*.csv') {
        $type = $file.BaseName.Substring(4)
        $arguments += "--relationships=${type}=$($file.FullName)"
    }
    Invoke-Client neo4j-admin $arguments
    return
}

$tables = @('categories', 'suppliers', 'warehouses', 'users', 'addresses', 'products',
    'product_categories', 'inventory', 'orders', 'order_items', 'payments', 'shipments', 'reviews')

foreach ($table in $tables) {
    $path = (Join-Path $root "sql/$table.csv").Replace('\', '/')
    if ($path.Contains("'") -or $path.Contains([char]10) -or $path.Contains([char]13)) {
        throw 'SQL import requires a dataset path without quotes or line breaks.'
    }
    $columns = (Get-Content -LiteralPath $path -TotalCount 1).Split(',')
    if ($Engine -eq 'postgresql') {
        $columnList = $columns -join ','
        $sql = "\copy $table ($columnList) FROM '$path' WITH (FORMAT csv, HEADER true, NULL '__ZTBD_NULL__', ENCODING 'UTF8')"
        Invoke-Client psql @('-X', '--dbname', $Database, '--set', 'ON_ERROR_STOP=1', '--command', $sql)
    } else {
        $variables = ($columns | ForEach-Object { "@$_" }) -join ','
        $assignments = ($columns | ForEach-Object { "$_ = NULLIF(@$_, '__ZTBD_NULL__')" }) -join ','
        $sql = @"
LOAD DATA LOCAL INFILE '$path' INTO TABLE $table CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES ($variables) SET $assignments
"@
        Invoke-Client mariadb @('--local-infile=1', '--show-warnings', '--database', $Database, '--execute', $sql)
    }
}
