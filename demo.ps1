# HAIL TO ANTHONY NOCENTINO THE WONDERFUL and his buttery voice.

# will need ollama to be set up and running
#region setup

Set-Location /workspaces/sql_for_devcontainer/

if (-not (Get-InstalledPSResource -Name dbatools -ErrorAction SilentlyContinue)) {
    Install-PSResource dbatools -TrustRepository
}

Set-DbatoolsInsecureConnection

$database = "släktingar"
$TableName = "vänner"


# path to ollama exposed via devtunnel if running in a codespace
$uri = "https://67fdmt48-11434.uks1.devtunnels.ms/api/embed"

#create connection to SQL Server running in the devcontainer
$secStringPassword = 'P@ssw0rd' | ConvertTo-SecureString -AsPlainText -Force
[pscredential]$cred = New-Object System.Management.Automation.PSCredential ('sa', $secStringPassword)
$sql = Connect-DbaInstance -SqlInstance localhost -SqlCredential $cred

# I KNOW I KNOW but this is a demo and I want to keep the output pretty and I dont have time to find out why dbatools throws that warning.
$WarningPreference = 'SilentlyContinue'

$PSDefaultParameterValues = @{
    '*Dba*:SqlInstance' = $sql
    '*Dba*:Database' = $database
    '*Dba*:Table' = $TableName
}

#create a new database
$DatabaseConfig = @{
    Name = $database
    RecoveryModel = 'Full'
}
if(-not (Get-DbaDatabase )) {
    Write-Host "Creating database $database" -ForegroundColor Green
    New-DbaDatabase @DatabaseConfig
} else {
    Write-Host "Database $database already exists" -ForegroundColor blue

}

$newTable = @"
CREATE TABLE {0} (
    Number INT PRIMARY KEY,
    Company NVARCHAR(255),
    Job NVARCHAR(255),
    Diet NVARCHAR(100),
    Travel NVARCHAR(255),
    Languages NVARCHAR(255),
    Country NVARCHAR(100),
    embeddings VECTOR(768)
);
"@ -f $TableName

if(-not (Get-DbaDbTable -Table $TableName)){
    Write-Host "Creating table $TableName" -ForegroundColor Green
    Invoke-DbaQuery -Query $newTable
} else {
    Write-Host "Table $TableName already exists" -ForegroundColor Blue
}


#endregion

#region function definition
function New-EmbeddingsGenerationFromCSV {
    param (
        [string]$CsvPath,
        [string]$Uri,
        [string]$TableName = "vänner"
    )

    $csv = Import-Csv -Path $CsvPath
    ############################################################################################################
    # Generate embeddings for each row in the datatable
    ############################################################################################################

    # Create DataTable Object
    $table = New-Object system.Data.DataTable $TableName
    # Create Columns
    $col1 = New-Object system.Data.DataColumn Number, ([decimal])
    $col2 = New-Object system.Data.DataColumn Company, ([string])
    $col3 = New-Object system.Data.DataColumn Job, ([string])
    $col4 = New-Object system.Data.DataColumn Diet, ([string])
    $col5 = New-Object system.Data.DataColumn Travel, ([string])
    $col6 = New-Object system.Data.DataColumn Languages, ([string])
    $col7 = New-Object system.Data.DataColumn Country, ([string])
    $col8 = New-Object system.Data.DataColumn Embeddings, ([string])

    #Add the Columns to the table
    $table.columns.add($col1)
    $table.columns.add($col2)
    $table.columns.add($col3)
    $table.columns.add($col4)
    $table.columns.add($col5)
    $table.columns.add($col6)
    $table.columns.add($col7)
    $table.columns.add($col8)

    foreach ($person in $csv) {
        $message = "Doing Number {0} " -f $person.Number
        Write-Host $message -ForegroundColor Cyan
        # Prepare the string for embeddings
        $string = $person.Diet, $person.Languages, $person.Country -join ' '
        # Create the body for the embeddings API
        $body = @{
            model = "nomic-embed-text"
            input = $string
        } | ConvertTo-Json -Depth 10 -Compress

        # Send the POST request for embeddings
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body

        # Create a new Row
        $row = $table.NewRow()
        $row.Company = $person.Company
        $row.Country = $person.Country
        $row.Diet = $person.Diet
        $row.Job = $person.Job
        $row.Languages = $person.Languages
        $row.Number = $person.Number
        $row.Travel = $person.Travel
        $row.embeddings = ($response.embeddings | ConvertTo-Json -Depth 10 -Compress) # Store as JSON string
        #Add new row to table
        $table.Rows.Add($row)
    }
    return $table
}
function New-SearchEmbedding {
    param (
        [string]$SearchText,
        [string]$Uri
    )

    $body = @{
        model = "nomic-embed-text"
        input = $SearchText
    } | ConvertTo-Json -Depth 10 -Compress

    # Send the POST request for embeddings
    $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Body $body
    return ($response.embeddings | ConvertTo-Json -Depth 10 -Compress) # Store as JSON string
}

function Get-Top10SimilarEmbeddings {
    param (
        [string]$SearchEmbedding,
        [pscustomobject]$SqlInstance,
        [string]$Database
    )
    $query = @"
    DECLARE @search_vector VECTOR(768) = '$searchEmbedding';

    SELECT TOP(10)
    --    p.Number,
        vector_distance('cosine', @search_vector, p.embeddings) AS distance,
    --  p.[Company],
     -- p.[Job],
      p.[Diet],
   --   p.[Travel],
      p.[Languages],
      p.[Country] --,
     -- p.[embeddings]
  FROM [släktingar].[dbo].[vänner] p
    ORDER BY distance ASC;
"@
    $results = Invoke-DbaQuery -Query $query

    return $results
}

function Get-Top100SimilarEmbeddings {
    param (
        [string]$SearchEmbedding,
        [pscustomobject]$SqlInstance,
        [string]$Database
    )
    $query = @"
    DECLARE @search_vector VECTOR(768) = '$searchEmbedding';

    SELECT TOP(100)
    --    p.Number,
        vector_distance('cosine', @search_vector, p.embeddings) AS distance,
    --  p.[Company],
     -- p.[Job],
      p.[Diet],
   --   p.[Travel],
      p.[Languages],
      p.[Country] --,
     -- p.[embeddings]
  FROM [släktingar].[dbo].[vänner] p
    ORDER BY distance ASC;
"@
    $results = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $query -Database $Database
    return $results
}
#endregion

# Import the CSV file and generate embeddings

$table = New-EmbeddingsGenerationFromCSV -CsvPath ./peoples.csv -Uri $uri -TableName $tableName

$Table | Select-Object -First 10 Number, Country, Embeddings| Format-Table -AutoSize

# Write the updated data back to the database, using this method for better than row by row for performance
$Table | Write-DbaDbTableData

# Use natural language to search the data by creating an embedding for the search text and then finding the top 10 most similar embeddings in the database using cosine similarity vector function in SQLServer 2025
$SearchText = 'I am looking for vegetarians who have travelled from Sweden'
$searchEmbedding = New-SearchEmbedding -SearchText $SearchText -Uri $uri
Get-Top10SimilarEmbeddings -SearchEmbedding $searchEmbedding -SqlInstance $sql -Database $database | Format-Table -AutoSize -Wrap

$SearchText = 'I am looking for people who have travelled from Scandinavia'
$searchEmbedding = New-SearchEmbedding -SearchText $SearchText -Uri $uri
Get-Top10SimilarEmbeddings -SearchEmbedding $searchEmbedding -SqlInstance $sql -Database $database | Format-Table -AutoSize -Wrap

$SearchText = 'What is most common diet for scandinavians?'
$searchEmbedding = New-SearchEmbedding -SearchText $SearchText -Uri $uri
Get-Top10SimilarEmbeddings -SearchEmbedding $searchEmbedding -SqlInstance $sql -Database $database | Format-Table -AutoSize -Wrap
