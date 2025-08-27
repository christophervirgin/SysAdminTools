-- ================================================================
-- SQL Server Column Inventory and Sensitive Data Detection System
-- Database Setup Script
-- ================================================================

-- Create schema for inventory management
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'inventory')
    EXEC('CREATE SCHEMA [inventory]')
GO

-- ================================================================
-- CORE TABLES
-- ================================================================

-- Main instance tracking table
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'SQLInstances' AND schema_id = SCHEMA_ID('inventory'))
BEGIN
    CREATE TABLE inventory.SQLInstances (
        InstanceID INT IDENTITY(1,1) PRIMARY KEY,
        ServerName NVARCHAR(128) NOT NULL,
        InstanceName NVARCHAR(128) NOT NULL,
        FullInstanceName NVARCHAR(256) NOT NULL,
        DiscoveredDate DATETIME2 DEFAULT GETDATE(),
        IsActive BIT DEFAULT 1,
        LastSuccessfulConnection DATETIME2 NULL,
        ConsecutiveFailures INT DEFAULT 0,
        UNIQUE(ServerName, InstanceName)
    )
END
GO

-- Connection attempt log
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ConnectionLog' AND schema_id = SCHEMA_ID('inventory'))
BEGIN
    CREATE TABLE inventory.ConnectionLog (
        LogID INT IDENTITY(1,1) PRIMARY KEY,
        InstanceID INT FOREIGN KEY REFERENCES inventory.SQLInstances(InstanceID),
        AttemptDate DATETIME2 DEFAULT GETDATE(),
        Success BIT,
        ErrorNumber INT NULL,
        ErrorMessage NVARCHAR(4000) NULL,
        DatabasesFound INT NULL,
        ColumnsInventoried INT NULL,
        Duration_ms INT NULL,
        INDEX IX_AttemptDate (AttemptDate) INCLUDE (InstanceID, Success)
    )
END
GO

-- Sensitive data patterns table
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'SensitiveDataPatterns' AND schema_id = SCHEMA_ID('inventory'))
BEGIN
    CREATE TABLE inventory.SensitiveDataPatterns (
        PatternID INT IDENTITY(1,1) PRIMARY KEY,
        CategoryName NVARCHAR(50) NOT NULL,
        PatternName NVARCHAR(100) NOT NULL,
        ColumnNamePattern NVARCHAR(500) NOT NULL,
        DataTypePattern NVARCHAR(100) NULL,
        RiskLevel NVARCHAR(20) NOT NULL CHECK (RiskLevel IN ('Critical', 'High', 'Medium', 'Low')),
        ComplianceFramework NVARCHAR(100) NULL,
        Description NVARCHAR(1000) NULL,
        IsActive BIT DEFAULT 1,
        CreatedDate DATETIME2 DEFAULT GETDATE()
    )
END
GO

-- Detected sensitive columns table
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'SensitiveColumns' AND schema_id = SCHEMA_ID('inventory'))
BEGIN
    CREATE TABLE inventory.SensitiveColumns (
        SensitiveColumnID INT IDENTITY(1,1) PRIMARY KEY,
        ServerName NVARCHAR(128),
        InstanceName NVARCHAR(128), 
        DatabaseName NVARCHAR(128),
        SchemaName NVARCHAR(128),
        TableName NVARCHAR(128),
        ColumnName NVARCHAR(128),
        DataType NVARCHAR(128),
        CategoryName NVARCHAR(50),
        PatternName NVARCHAR(100),
        RiskLevel NVARCHAR(20),
        ComplianceFramework NVARCHAR(100),
        DetectedDate DATETIME2 DEFAULT GETDATE(),
        IsConfirmed BIT NULL, -- NULL = Not reviewed, 1 = Confirmed sensitive, 0 = False positive
        ReviewedBy NVARCHAR(128) NULL,
        ReviewedDate DATETIME2 NULL,
        Notes NVARCHAR(1000) NULL,
        INDEX IX_Server_Database (ServerName, DatabaseName),
        INDEX IX_RiskLevel (RiskLevel),
        INDEX IX_Category (CategoryName)
    )
END
GO

-- ================================================================
-- SENSITIVE DATA PATTERNS
-- ================================================================

-- Insert comprehensive sensitive data patterns
IF NOT EXISTS (SELECT 1 FROM inventory.SensitiveDataPatterns)
BEGIN
    INSERT INTO inventory.SensitiveDataPatterns (CategoryName, PatternName, ColumnNamePattern, DataTypePattern, RiskLevel, ComplianceFramework, Description)
    VALUES 
        -- Personal Identifiers (Critical Risk)
        ('PII', 'Social Security Number', '%ssn%|%social%security%|%taxpayer%id%', 'char|varchar|nchar|nvarchar', 'Critical', 'GDPR,HIPAA,SOX', 'Social Security Numbers or Tax IDs'),
        ('PII', 'Driver License', '%driver%license%|%dl%number%|%license%no%', 'char|varchar|nchar|nvarchar', 'High', 'GDPR', 'Driver license numbers'),
        ('PII', 'Passport Number', '%passport%|%passport%number%|%passport%no%', 'char|varchar|nchar|nvarchar', 'High', 'GDPR', 'Passport identification numbers'),
        ('PII', 'National ID', '%national%id%|%citizen%id%|%identity%number%', 'char|varchar|nchar|nvarchar', 'High', 'GDPR', 'National identification numbers'),
        
        -- Financial Data (Critical Risk)
        ('Financial', 'Credit Card', '%credit%card%|%cc%number%|%card%no%|%pan%', 'char|varchar|nchar|nvarchar', 'Critical', 'PCI-DSS', 'Credit card numbers'),
        ('Financial', 'Bank Account', '%account%number%|%routing%|%iban%|%swift%', 'char|varchar|nchar|nvarchar', 'Critical', 'PCI-DSS,SOX', 'Bank account information'),
        ('Financial', 'Financial Amount', '%salary%|%income%|%wage%|%payment%|%balance%|%amount%', 'money|decimal|numeric|float', 'High', 'SOX', 'Financial amounts and salaries'),
        
        -- Authentication (Critical Risk)
        ('Auth', 'Password', '%password%|%pwd%|%pass%|%secret%|%key%', 'char|varchar|nchar|nvarchar|binary|varbinary', 'Critical', 'All', 'Authentication credentials'),
        ('Auth', 'API Keys', '%api%key%|%token%|%secret%key%|%access%key%', 'char|varchar|nchar|nvarchar', 'Critical', 'All', 'API keys and tokens'),
        ('Auth', 'Hash/Salt', '%hash%|%salt%|%digest%', 'char|varchar|nchar|nvarchar|binary|varbinary', 'High', 'All', 'Password hashes and salts'),
        
        -- Contact Information (Medium-High Risk)
        ('Contact', 'Email Address', '%email%|%mail%|%e_mail%', 'char|varchar|nchar|nvarchar', 'Medium', 'GDPR,CAN-SPAM', 'Email addresses'),
        ('Contact', 'Phone Number', '%phone%|%tel%|%mobile%|%cell%|%fax%', 'char|varchar|nchar|nvarchar', 'Medium', 'GDPR', 'Phone and fax numbers'),
        ('Contact', 'Address', '%address%|%street%|%zip%|%postal%|%city%|%state%', 'char|varchar|nchar|nvarchar', 'Medium', 'GDPR', 'Physical addresses'),
        
        -- Health Information (Critical Risk)
        ('Health', 'Medical Record', '%medical%|%patient%|%diagnosis%|%treatment%|%prescription%', 'char|varchar|nchar|nvarchar', 'Critical', 'HIPAA', 'Medical information'),
        ('Health', 'Insurance', '%insurance%|%policy%number%|%member%id%|%group%number%', 'char|varchar|nchar|nvarchar', 'High', 'HIPAA', 'Insurance information'),
        
        -- Biometric Data (Critical Risk)
        ('Biometric', 'Fingerprint', '%fingerprint%|%biometric%|%thumbprint%', 'binary|varbinary|image', 'Critical', 'GDPR,BIPA', 'Biometric identifiers'),
        ('Biometric', 'Facial Recognition', '%face%|%facial%|%photo%|%image%', 'binary|varbinary|image', 'High', 'GDPR,BIPA', 'Facial recognition data'),
        
        -- Demographic Data (Medium Risk)
        ('Demographic', 'Date of Birth', '%birth%|%dob%|%born%|%age%', 'date|datetime|datetime2', 'Medium', 'GDPR,HIPAA', 'Birth dates and age'),
        ('Demographic', 'Gender', '%gender%|%sex%', 'char|varchar|nchar|nvarchar', 'Low', 'GDPR', 'Gender information'),
        ('Demographic', 'Race/Ethnicity', '%race%|%ethnic%|%nationality%', 'char|varchar|nchar|nvarchar', 'Medium', 'GDPR', 'Race and ethnicity data'),
        
        -- Location Data (Medium Risk)
        ('Location', 'GPS Coordinates', '%lat%|%long%|%coordinate%|%gps%|%geolocation%', 'decimal|numeric|float|geography', 'Medium', 'GDPR', 'Geographic coordinates'),
        ('Location', 'IP Address', '%ip%address%|%ipaddr%', 'char|varchar|nchar|nvarchar', 'Medium', 'GDPR', 'IP addresses'),
        
        -- Employment Data (Medium Risk)
        ('Employment', 'Employee ID', '%employee%id%|%emp%id%|%staff%id%|%badge%', 'char|varchar|nchar|nvarchar|int', 'Medium', 'GDPR', 'Employee identifiers'),
        ('Employment', 'Job Title', '%title%|%position%|%job%|%role%', 'char|varchar|nchar|nvarchar', 'Low', 'GDPR', 'Job titles and positions')
END
GO

-- ================================================================
-- FUNCTIONS
-- ================================================================

-- Enhanced sensitive data detection function
IF EXISTS (SELECT 1 FROM sys.objects WHERE name = 'DetectSensitiveData' AND schema_id = SCHEMA_ID('inventory'))
    DROP FUNCTION inventory.DetectSensitiveData
GO

CREATE FUNCTION inventory.DetectSensitiveData
(
    @ColumnName NVARCHAR(128),
    @DataType NVARCHAR(128)
)
RETURNS TABLE
AS
RETURN
(
    SELECT TOP 1
        p.CategoryName,
        p.PatternName,
        p.RiskLevel,
        p.ComplianceFramework,
        p.Description
    FROM inventory.SensitiveDataPatterns p
    WHERE p.IsActive = 1
      AND (
          -- Column name pattern matching using OR logic for pipe-separated patterns
          (@ColumnName LIKE '%ssn%' AND p.ColumnNamePattern LIKE '%ssn%') OR
          (@ColumnName LIKE '%social%' AND p.ColumnNamePattern LIKE '%social%') OR
          (@ColumnName LIKE '%password%' AND p.ColumnNamePattern LIKE '%password%') OR
          (@ColumnName LIKE '%email%' AND p.ColumnNamePattern LIKE '%email%') OR
          (@ColumnName LIKE '%phone%' AND p.ColumnNamePattern LIKE '%phone%') OR
          (@ColumnName LIKE '%credit%' AND p.ColumnNamePattern LIKE '%credit%') OR
          (@ColumnName LIKE '%card%' AND p.ColumnNamePattern LIKE '%card%') OR
          (@ColumnName LIKE '%account%' AND p.ColumnNamePattern LIKE '%account%') OR
          (@ColumnName LIKE '%salary%' AND p.ColumnNamePattern LIKE '%salary%') OR
          (@ColumnName LIKE '%birth%' AND p.ColumnNamePattern LIKE '%birth%') OR
          (@ColumnName LIKE '%dob%' AND p.ColumnNamePattern LIKE '%dob%') OR
          (@ColumnName LIKE '%address%' AND p.ColumnNamePattern LIKE '%address%') OR
          (@ColumnName LIKE '%driver%' AND p.ColumnNamePattern LIKE '%driver%') OR
          (@ColumnName LIKE '%passport%' AND p.ColumnNamePattern LIKE '%passport%') OR
          (@ColumnName LIKE '%medical%' AND p.ColumnNamePattern LIKE '%medical%') OR
          (@ColumnName LIKE '%patient%' AND p.ColumnNamePattern LIKE '%patient%')
      )
      AND (
          p.DataTypePattern IS NULL 
          OR @DataType LIKE '%' + p.DataTypePattern + '%'
          OR (@DataType LIKE '%char%' AND p.DataTypePattern LIKE '%char%')
          OR (@DataType LIKE '%varchar%' AND p.DataTypePattern LIKE '%varchar%')
          OR (@DataType LIKE '%money%' AND p.DataTypePattern LIKE '%money%')
          OR (@DataType LIKE '%decimal%' AND p.DataTypePattern LIKE '%decimal%')
          OR (@DataType LIKE '%date%' AND p.DataTypePattern LIKE '%date%')
      )
    ORDER BY 
        CASE p.RiskLevel 
            WHEN 'Critical' THEN 1
            WHEN 'High' THEN 2  
            WHEN 'Medium' THEN 3
            WHEN 'Low' THEN 4
        END,
        LEN(p.ColumnNamePattern) DESC -- More specific patterns first
)
GO

-- ================================================================
-- STORED PROCEDURES
-- ================================================================

-- Stored proc to log connection attempts
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'LogConnectionAttempt' AND schema_id = SCHEMA_ID('inventory'))
    DROP PROCEDURE inventory.LogConnectionAttempt
GO

CREATE PROCEDURE inventory.LogConnectionAttempt
    @ServerName NVARCHAR(128),
    @InstanceName NVARCHAR(128),
    @Success BIT,
    @ErrorNumber INT = NULL,
    @ErrorMessage NVARCHAR(4000) = NULL,
    @DatabasesFound INT = NULL,
    @ColumnsInventoried INT = NULL,
    @Duration_ms INT = NULL
AS
BEGIN
    SET NOCOUNT ON
    
    DECLARE @InstanceID INT
    
    -- Ensure instance exists in tracking table
    SELECT @InstanceID = InstanceID 
    FROM inventory.SQLInstances 
    WHERE ServerName = @ServerName AND InstanceName = @InstanceName
    
    IF @InstanceID IS NULL
    BEGIN
        DECLARE @FullInstanceName NVARCHAR(256) = 
            CASE 
                WHEN @InstanceName = 'DEFAULT' THEN @ServerName
                ELSE @ServerName + '\' + @InstanceName
            END
            
        INSERT INTO inventory.SQLInstances (ServerName, InstanceName, FullInstanceName)
        VALUES (@ServerName, @InstanceName, @FullInstanceName)
        
        SET @InstanceID = SCOPE_IDENTITY()
    END
    
    -- Log the connection attempt
    INSERT INTO inventory.ConnectionLog 
        (InstanceID, Success, ErrorNumber, ErrorMessage, DatabasesFound, ColumnsInventoried, Duration_ms)
    VALUES 
        (@InstanceID, @Success, @ErrorNumber, @ErrorMessage, @DatabasesFound, @ColumnsInventoried, @Duration_ms)
    
    -- Update instance status
    IF @Success = 1
    BEGIN
        UPDATE inventory.SQLInstances 
        SET LastSuccessfulConnection = GETDATE(),
            ConsecutiveFailures = 0
        WHERE InstanceID = @InstanceID
    END
    ELSE
    BEGIN
        UPDATE inventory.SQLInstances 
        SET ConsecutiveFailures = ConsecutiveFailures + 1
        WHERE InstanceID = @InstanceID
    END
END
GO

-- Procedure to analyze and store sensitive data findings
IF EXISTS (SELECT 1 FROM sys.procedures WHERE name = 'AnalyzeSensitiveData' AND schema_id = SCHEMA_ID('inventory'))
    DROP PROCEDURE inventory.AnalyzeSensitiveData
GO

CREATE PROCEDURE inventory.AnalyzeSensitiveData
    @ServerName NVARCHAR(128),
    @InstanceName NVARCHAR(128),
    @DatabaseName NVARCHAR(128),
    @SchemaName NVARCHAR(128),
    @TableName NVARCHAR(128),
    @ColumnName NVARCHAR(128),
    @DataType NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON
    
    DECLARE @CategoryName NVARCHAR(50)
    DECLARE @PatternName NVARCHAR(100) 
    DECLARE @RiskLevel NVARCHAR(20)
    DECLARE @ComplianceFramework NVARCHAR(100)
    
    -- Detect sensitive data pattern
    SELECT 
        @CategoryName = CategoryName,
        @PatternName = PatternName,
        @RiskLevel = RiskLevel,
        @ComplianceFramework = ComplianceFramework
    FROM inventory.DetectSensitiveData(@ColumnName, @DataType)
    
    -- If sensitive data detected, store it
    IF @CategoryName IS NOT NULL
    BEGIN
        -- Check if already exists
        IF NOT EXISTS (
            SELECT 1 FROM inventory.SensitiveColumns 
            WHERE ServerName = @ServerName 
              AND InstanceName = @InstanceName
              AND DatabaseName = @DatabaseName 
              AND SchemaName = @SchemaName
              AND TableName = @TableName 
              AND ColumnName = @ColumnName
        )
        BEGIN
            INSERT INTO inventory.SensitiveColumns 
                (ServerName, InstanceName, DatabaseName, SchemaName, TableName, ColumnName, 
                 DataType, CategoryName, PatternName, RiskLevel, ComplianceFramework)
            VALUES 
                (@ServerName, @InstanceName, @DatabaseName, @SchemaName, @TableName, @ColumnName,
                 @DataType, @CategoryName, @PatternName, @RiskLevel, @ComplianceFramework)
        END
        ELSE
        BEGIN
            -- Update existing record with latest detection
            UPDATE inventory.SensitiveColumns
            SET DataType = @DataType,
                CategoryName = @CategoryName,
                PatternName = @PatternName,
                RiskLevel = @RiskLevel,
                ComplianceFramework = @ComplianceFramework,
                DetectedDate = GETDATE()
            WHERE ServerName = @ServerName 
              AND InstanceName = @InstanceName
              AND DatabaseName = @DatabaseName 
              AND SchemaName = @SchemaName
              AND TableName = @TableName 
              AND ColumnName = @ColumnName
        END
    END
END
GO

-- ================================================================
-- VIEWS
-- ================================================================

-- View for current instance status
IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'InstanceStatus' AND schema_id = SCHEMA_ID('inventory'))
    DROP VIEW inventory.InstanceStatus
GO

CREATE VIEW inventory.InstanceStatus AS
SELECT 
    si.ServerName,
    si.InstanceName,
    si.FullInstanceName,
    si.DiscoveredDate,
    si.LastSuccessfulConnection,
    si.ConsecutiveFailures,
    CASE 
        WHEN si.ConsecutiveFailures = 0 THEN 'Healthy'
        WHEN si.ConsecutiveFailures BETWEEN 1 AND 2 THEN 'Warning'
        WHEN si.ConsecutiveFailures >= 3 THEN 'Critical'
    END AS HealthStatus,
    recent.LastAttempt,
    recent.LastError,
    recent.TotalDatabases,
    recent.TotalColumns
FROM inventory.SQLInstances si
OUTER APPLY (
    SELECT TOP 1
        cl.AttemptDate AS LastAttempt,
        cl.ErrorMessage AS LastError,
        cl.DatabasesFound AS TotalDatabases,
        cl.ColumnsInventoried AS TotalColumns
    FROM inventory.ConnectionLog cl
    WHERE cl.InstanceID = si.InstanceID
    ORDER BY cl.AttemptDate DESC
) recent
WHERE si.IsActive = 1
GO

-- Sensitive data summary by risk level
IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'SensitiveDataSummary' AND schema_id = SCHEMA_ID('inventory'))
    DROP VIEW inventory.SensitiveDataSummary
GO

CREATE VIEW inventory.SensitiveDataSummary AS
SELECT 
    RiskLevel,
    CategoryName,
    COUNT(*) AS ColumnCount,
    COUNT(DISTINCT ServerName + '.' + DatabaseName) AS DatabaseCount,
    COUNT(DISTINCT ServerName) AS ServerCount,
    STRING_AGG(DISTINCT ComplianceFramework, ', ') AS ComplianceFrameworks
FROM inventory.SensitiveColumns
WHERE IsConfirmed IS NULL OR IsConfirmed = 1  -- Exclude confirmed false positives
GROUP BY RiskLevel, CategoryName
GO

-- Detailed sensitive data inventory
IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'SensitiveDataInventory' AND schema_id = SCHEMA_ID('inventory'))
    DROP VIEW inventory.SensitiveDataInventory
GO

CREATE VIEW inventory.SensitiveDataInventory AS
SELECT 
    sc.ServerName,
    sc.InstanceName,
    sc.DatabaseName,
    sc.SchemaName,
    sc.TableName,
    sc.ColumnName,
    sc.DataType,
    sc.CategoryName,
    sc.PatternName,
    sc.RiskLevel,
    sc.ComplianceFramework,
    sc.DetectedDate,
    CASE 
        WHEN sc.IsConfirmed IS NULL THEN 'Pending Review'
        WHEN sc.IsConfirmed = 1 THEN 'Confirmed Sensitive'
        WHEN sc.IsConfirmed = 0 THEN 'False Positive'
    END AS ReviewStatus,
    sc.ReviewedBy,
    sc.ReviewedDate,
    sc.Notes
FROM inventory.SensitiveColumns sc
GO

-- Critical findings that need immediate attention
IF EXISTS (SELECT 1 FROM sys.views WHERE name = 'CriticalFindings' AND schema_id = SCHEMA_ID('inventory'))
    DROP VIEW inventory.CriticalFindings
GO

CREATE VIEW inventory.CriticalFindings AS
SELECT 
    ServerName,
    InstanceName, 
    DatabaseName,
    COUNT(*) AS CriticalColumns,
    STRING_AGG(SchemaName + '.' + TableName + '.' + ColumnName, ', ') AS AffectedColumns,
    STRING_AGG(DISTINCT CategoryName, ', ') AS Categories,
    STRING_AGG(DISTINCT ComplianceFramework, ', ') AS ComplianceImpact
FROM inventory.SensitiveColumns
WHERE RiskLevel = 'Critical' 
  AND (IsConfirmed IS NULL OR IsConfirmed = 1)
GROUP BY ServerName, InstanceName, DatabaseName
HAVING COUNT(*) > 0
GO

PRINT 'Database setup completed successfully!'
PRINT 'Created schema: inventory'
PRINT 'Created tables: SQLInstances, ConnectionLog, SensitiveDataPatterns, SensitiveColumns'
PRINT 'Created functions: DetectSensitiveData'
PRINT 'Created procedures: LogConnectionAttempt, AnalyzeSensitiveData'
PRINT 'Created views: InstanceStatus, SensitiveDataSummary, SensitiveDataInventory, CriticalFindings'
PRINT 'Populated ' + CAST((SELECT COUNT(*) FROM inventory.SensitiveDataPatterns) AS VARCHAR) + ' sensitive data patterns'