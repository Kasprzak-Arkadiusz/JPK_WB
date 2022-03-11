USE MS_Business_Intelligence
GO

IF EXISTS (SELECT *
           FROM   sys.objects
           WHERE  object_id = OBJECT_ID(N'[dbo].[STR2DATE]')
                  AND type IN ( N'FN', N'IF', N'TF', N'FS', N'FT' ))
  DROP FUNCTION [dbo].[STR2DATE]
GO

CREATE FUNCTION [dbo].[STR2DATE] (@str varchar(10))
RETURNS date
AS
    BEGIN
       Return CAST(@str as date)
    END
GO


IF EXISTS (SELECT *
           FROM   sys.objects
           WHERE  object_id = OBJECT_ID(N'[dbo].[RemoveWhitespaces]')
                  AND type IN ( N'FN', N'IF', N'TF', N'FS', N'FT' ))
  DROP FUNCTION [dbo].[RemoveWhitespaces]
GO

CREATE FUNCTION [dbo].[RemoveWhitespaces] (@str varchar(250))
RETURNS varchar(34)
AS
    BEGIN
       Return rtrim(ltrim(replace(replace(replace(@str,char(9),' '),char(10),' '),char(13),' ')))
    END
GO

IF EXISTS (SELECT *
           FROM   sys.objects
           WHERE  object_id = OBJECT_ID(N'[dbo].[STR2DECIMAL]')
                  AND type IN ( N'FN', N'IF', N'TF', N'FS', N'FT' ))
  DROP FUNCTION [dbo].[STR2DECIMAL]
GO

CREATE FUNCTION [dbo].[STR2DECIMAL] (@str varchar(20))
RETURNS decimal(18,2)
AS
    BEGIN
        SELECT @str = [dbo].RemoveWhitespaces(@str)
        DECLARE @commaIndex int = CHARINDEX(',',@str)
        IF @commaIndex > 0
           SELECT @str = REPLACE(@str, ',', '.')

        Return CAST(@str as decimal(18,2))
    END
GO

IF NOT EXISTS
(	SELECT 1
		from sys.objects o (NOLOCK)
		WHERE	(o.[name] = 'ValidateNaglowek_imp_tmp')
		AND		(OBJECTPROPERTY(o.object_id,'IsProcedure') = 1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.ValidateNaglowek_imp_tmp AS '
	EXEC sp_sqlexec @stmt
END
GO

Alter Procedure [dbo].[ValidateNaglowek_imp_tmp] (@errno int = 0 output)
AS
    SET @errno = 0

    DECLARE @numberOfResults int, @err_code nchar(20), @err_msg nvarchar(100)
    SET @err_code = 'Naglowek_imp_tmp'

    -- Sprawdzamy, czy w kolumnie 'Numer' znajdują się unikalne wartości
    SELECT @numberOfResults = COUNT(Distinct n.Numer)
        FROM Naglowek_imp_tmp n

    IF @numberOfResults <> (SELECT COUNT(n.Numer) FROM Naglowek_imp_tmp n)
    begin
        SET @err_msg = N'Plik z nagłówkiem posiada zduplikowane wartości w kolumnie ''Numer'''
        INSERT INTO LOG(OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy, czy dane nagłówka dotyczą tylko jednego klienta
    SELECT @numberOfResults = COUNT(Distinct n.NIP)
        FROM Naglowek_imp_tmp n

    IF @numberOfResults IS NOT NULL AND (@numberOfResults > 1)
    begin
        SET @err_msg = N'Plik z nagłówkiem posiada różne wartości NIP'
        INSERT INTO LOG(OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy, czy kod kraju ma tylko wartości 'PL'
    SELECT @numberOfResults = COUNT(*)
        FROM Naglowek_imp_tmp n
        WHERE n.KodKraju <> 'PL'

    IF @numberOfResults > 0
    begin
        SET @err_msg = N'Kod kraju powinien mieć wartość ''PL'''
        INSERT INTO LOG(OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    SELECT @numberOfResults = COUNT(Distinct n.NumerRachunku)
        FROM Naglowek_imp_tmp n

    IF @numberOfResults <> 1
    begin
        SET @err_msg = N'Liczba rachunków bankowych jest różna od 1'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy, czy numer rachunku bankowego jest w formacie IBAN
    SELECT @numberOfResults = COUNT(*)
        FROM Naglowek_imp_tmp n
        WHERE LTRIM(RTRIM(n.NumerRachunku)) not like '[P][L][0-9][0-9]%'

    IF @numberOfResults > 0
    begin
        SET @err_msg = N'Rachunek bankowy nie jest w formacie IBAN'
        INSERT INTO LOG(OpisBledu, DataWystapienia, KodBledu)
        VALUES(@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy, czy kod pocztowy jest w dobrym formacie [0-9]{2}[-][0-9]{3}
    SELECT @numberOfResults = COUNT(*)
        FROM Naglowek_imp_tmp n
        WHERE LTRIM(RTRIM(n.KodPocztowy)) not like '[0-9][0-9][-][0-9][0-9][0-9]'

    IF @numberOfResults > 0
    begin
        SET @err_msg = N'Kod pocztowy jest w złym formacie'
        INSERT INTO LOG(OpisBledu, DataWystapienia, KodBledu)
        VALUES(@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    IF OBJECT_ID('tempdb..#Dates') IS NOT NULL
    begin
        drop table #Dates
    end

    Create table #Dates (DataOd date, DataDo date)

    -- Sprawdzamy poprawność formatu dat
    BEGIN TRY
        INSERT INTO #Dates SELECT [dbo].STR2DATE(n.DataOd),
           [dbo].STR2DATE(n.DataDo)
        FROM Naglowek_imp_tmp n
    end try
    begin catch
        SET @err_msg = N'Błędny format daty'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end catch

    -- Sprawdzamy, czy data do jest wcześniej niż data od
    SELECT @numberOfResults = COUNT(*)
        FROM #Dates d
        WHERE d.DataDo < d.DataOd

    IF @numberOfResults > 0
    begin
        SET @err_msg = N'''DataDo'' nie może być wcześniej niż ''DataOd'''
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy poprawność formatu sald
    BEGIN TRY
        SELECT [dbo].STR2DECIMAL(n.SaldoPoczatkowe) as SaldoPoczatkowe,
           [dbo].STR2DECIMAL(n.SaldoKoncowe) as SaldoKoncowe
        INTO #Decimals
        FROM Naglowek_imp_tmp n
    end try
    begin catch
        SET @err_msg = N'Błędny format pól walutowych'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end catch
GO

/*  Things to validate:
        + Verify that 'Numer' column has unique values
        + File should have only data related to one client (Podmiot)
        + Check that KodKraju value is equal to 'PL'
        + File should have only one bank account (rachunekBankowy)
        + Check that NumerRachunku is in the IBAN format
        + Check format of KodPocztowy column
        + Date format (DataOd and DataDo)
        + DataOd should be prior to or the same as DataDo
        + Check that decimal columns are in the correct format (SaldoPoczątkowe, SaldoKońcowe)
*/

Exec ValidateNaglowek_imp_tmp @errno = 0

IF NOT EXISTS
(	SELECT 1
		from sys.objects o (NOLOCK)
		WHERE	(o.[name] = 'ValidateWiersz_imp_tmp')
		AND		(OBJECTPROPERTY(o.object_id,'IsProcedure') = 1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.ValidateWiersz_imp_tmp AS '
	EXEC sp_sqlexec @stmt
END
GO

Alter Procedure [dbo].[ValidateWiersz_imp_tmp] (@errno int = 0 output)
AS
    SET @errno = 0

    DECLARE @numberOfResults int, @err_code nchar(20), @err_msg nvarchar(100)
    SET @err_code = N'WyciągWiersz_imp_tmp'

    -- Sprawdzamy, czy wartości w kolumnie NumerWiersza nie powtarzają się
    SELECT @numberOfResults = COUNT(Distinct w.NumerWiersza)
        FROM WyciagWiersz_imp_tmp w

    IF @numberOfResults <> (SELECT COUNT(w.NumerWiersza) FROM WyciagWiersz_imp_tmp w)
    begin
        SET @err_msg = N'Kolumna ''NumerWiersza'' nie ma unikalnych wartości'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    /* Odkomentować, jeśli nazwa podmiotu w Wyciąg wiersz określa podmiot, do którego należy rachunek bankowy. Jeśli
       natomiast podmiotem jest odbiorca, nadawca przelewu, to usunąć ten fragment

    -- Sprawdzamy, czy podany jest tylko jeden Podmiot
    SELECT @numberOfResults = COUNT(Distinct w.NazwaPodmiotu)
        FROM WyciagWiersz_imp_tmp w

    IF @numberOfResults <> 1
    begin
        SET @err_msg = N'Liczba podmiotów jest różna od 1'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end

    -- Sprawdzamy, czy podany podmiot jest taki sam jak w pliku z danymi do nagłówka
    DECLARE @headerSubject nvarchar(34), @statementSubject nvarchar(34)

    SELECT Distinct @headerSubject = n.NazwaPodmiotu FROM Naglowek_imp_tmp n
    SELECT Distinct @statementSubject = w.NazwaPodmiotu FROM WyciagWiersz_imp_tmp w

    SELECT @headerSubject = dbo.RemoveWhitespaces(@headerSubject)
    SELECT @statementSubject = dbo.RemoveWhitespaces(@statementSubject)

    IF @headerSubject <> @statementSubject
    begin
        SET @err_msg = N'Podmiot w pliku z wyciągami jest różny od podmiotu w pliku z danymi do nagłówka'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end*/

    -- Sprawdzamy poprawność formatu salda i kwoty
    BEGIN TRY
        SELECT [dbo].STR2DECIMAL(w.SaldoOperacji) as [SaldoOperacji],
           [dbo].STR2DECIMAL(w.KwotaOperacji) as [KwotaOperacji]
        INTO #Decimals
        FROM WyciagWiersz_imp_tmp w
    end try
    begin catch
        SET @err_msg = N'Błędny format pól walutowych'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end catch

    -- Sprawdzamy poprawność formatu daty operacji
    IF OBJECT_ID('tempdb..#Dates') IS NOT NULL
    begin
        drop table #Dates
    end

    Create table #Dates (operationDate date)

    BEGIN TRY
        INSERT INTO #Dates SELECT [dbo].STR2DATE(w.DataOperacji)
        FROM WyciagWiersz_imp_tmp w
    end try
    begin catch
        SET @err_msg = N'Błędny format daty'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end catch

    -- Sprawdzamy, czy data operacji jest w przedziale czasu określonym przez nagłówek
    SELECT @numberOfResults = COUNT(*) FROM WyciagWiersz_imp_tmp w
    LEFT JOIN Naglowek_imp_tmp n on n.Numer = w.Numer
    WHERE w.DataOperacji < n.DataOd OR w.DataOperacji > n.DataDo

    IF @numberOfResults > 0
    begin
        SET @err_msg = N'Data operacji nie znajduje się w przedziale czasu okreslonym przez nagłówek'
        INSERT INTO LOG (OpisBledu, DataWystapienia, KodBledu)
        VALUES (@err_msg, CURRENT_TIMESTAMP, @err_code)
        RAISERROR(@err_msg, 14, 1)
    end
GO

Exec ValidateWiersz_imp_tmp @errno = 0

/* Things to validate:
        + Column 'NumerWiersza' should be unique
        + File should have only data related to one bank account (RachunekBankowy) equal to column in Naglowek_imp_tmp
        + Check that KwotaOperacji and SaldoOperacji is in the correct format
        + Check that DataOperacji is in the correct format
        + Check that DataOperacji is within the time frame specifed by the header(nagłówek)
*/

/* Gdybym się nudził
   - Usunąć kolumnę 'NumerWiersza' z Excela i bazy danych
*/