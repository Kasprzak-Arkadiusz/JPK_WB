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
    Return CAST(@str as date)
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
		WHERE	(o.[name] = 'InsertData')
		AND		(OBJECTPROPERTY(o.object_id,'IsProcedure') = 1)
)
BEGIN
	DECLARE @stmt nvarchar(100)
	SET @stmt = 'CREATE PROCEDURE dbo.InsertData AS '
	EXEC sp_sqlexec @stmt
END
GO

Alter Procedure [dbo].[InsertData]
AS
    SET XACT_ABORT ON;
    BEGIN TRANSACTION [Transaction]

    -- Wstawiamy dane dotyczące tabeli RachunekBankowy
    IF OBJECT_ID('tempdb..#AccountNumbers') IS NOT NULL
        drop table #AccountNumbers

    SELECT n.NumerRachunku AS numerRachunku
    INTO #AccountNumbers
    FROM RachunekBankowy r
    RIGHT JOIN Naglowek_imp_tmp n on r.Numer = n.NumerRachunku
    WHERE r.Numer IS NULL

    -- Sprawdzamy, czy rachunek bankowy jest już w tabeli RachunekBankowy
    IF (SELECT COUNT(a.numerRachunku) FROM #AccountNumbers a) > 0
    begin
        INSERT INTO RachunekBankowy (Numer)
        (SELECT DISTINCT(a.numerRachunku) FROM #AccountNumbers a)
    end

    -- Wstawiamy dane dotyczące tabeli Podmiot
    IF OBJECT_ID('tempdb..#Subjects') IS NOT NULL
        drop table #Subjects

    SELECT n.NIP AS NIP,
           n.NazwaPodmiotu AS Nazwa,
           n.KodKraju AS KodKraju,
           n.Woj AS Woj,
           n.Powiat AS Powiat,
           n.Gmina AS Gmina,
           n.Ulica AS Ulica,
           n.NumerDomu AS NumerDomu,
           n.Miasto AS Miejscowosc,
           n.KodPocztowy AS KodPocztowy,
           n.Poczta AS Poczta,
           n.NumerRachunku AS NumerRachunku,
           ROW_NUMBER() OVER (PARTITION BY n.NIP ORDER BY p.Id) AS RowNumber
    INTO #Subjects
    FROM Podmiot p
    RIGHT JOIN Naglowek_imp_tmp n on p.NIP = n.NIP
    WHERE p.NIP IS NULL

    -- Wybieramy tylko niepowtarzające się podmioty
    IF OBJECT_ID('tempdb..#UniqueSubjects') IS NOT NULL
        drop table #UniqueSubjects

    SELECT *
    INTO #UniqueSubjects
    FROM #Subjects s
    WHERE s.RowNumber = 1

    -- Sprawdzamy, czy podmiot z podanym NIP jest już w tabeli Podmiot
    IF (SELECT COUNT(u.NIP) FROM #UniqueSubjects u) > 0
    begin
        INSERT INTO Podmiot (Nazwa, KodKraju, Woj, Powiat, Gmina, Miasto,
                             Ulica, Numer, NIP, KodPocztowy, Poczta, RachunekBankowy)
            (SELECT u.Nazwa, u.KodKraju, u.Woj, u.Powiat, u.Gmina, u.Miejscowosc,
                    u.Ulica, u.NumerDomu, u.Nip, u.KodPocztowy, u.Poczta, r.Id
            FROM #UniqueSubjects u
            JOIN RachunekBankowy r ON u.NumerRachunku = r.Numer)
    end

    -- Wstawiamy dane dotyczące tabeli Naglowek
    IF OBJECT_ID('tempdb..#Headers') IS NOT NULL
        drop table #Headers

    SELECT n.Numer AS Numer,
           dbo.STR2DATE(n.DataOd) AS DataOd,
           dbo.STR2DATE(n.DataDo) AS DataDo,
           n.KodUrzedu AS KodUrzedu,
           dbo.STR2DECIMAL(n.SaldoPoczatkowe) AS SaldoPoczatkowe,
           dbo.STR2DECIMAL(n.SaldoKoncowe) AS SaldoKoncowe,
           n.NIP AS NIP
    INTO #Headers
    FROM Naglowek na
    RIGHT JOIN Naglowek_imp_tmp n ON n.Numer = na.Numer
    WHERE na.Numer IS NULL

     -- Sprawdzamy, czy naglowek z podanym numerem jest już w tabeli Naglowek
    IF (SELECT COUNT(h.Numer) FROM #Headers h) > 0
    begin
        INSERT INTO Naglowek(DataOd, DataDo, KodUrzedu, Podmiot, SaldoPoczatkowe, SaldoKoncowe, Numer)
        SELECT h.DataOd, h.DataDo, h.KodUrzedu, p.Id, h.SaldoPoczatkowe, h.SaldoKoncowe, h.Numer FROM #Headers h
            JOIN Podmiot p ON p.NIP = h.NIP
    end

     -- Wstawiamy dane dotyczące tabeli WyciagWiersz
    IF OBJECT_ID('tempdb..#Rows') IS NOT NULL
        drop table #Rows

    SELECT WWit.Numer,
           WWit.NazwaPodmiotu,
           dbo.STR2DATE(WWit.DataOperacji) AS DataOperacji,
           WWit.OpisOperacji,
           WWit.NumerWiersza,
           dbo.STR2DECIMAL(WWit.KwotaOperacji) AS KwotaOperacji,
           dbo.STR2DECIMAL(WWit.SaldoOperacji) AS SaldoOperacji
    INTO #Rows
    FROM WyciagWiersz_imp_tmp WWit

    IF OBJECT_ID('tempdb..#UniqueRows') IS NOT NULL
        drop table #UniqueRows

    SELECT * INTO #UniqueRows
    FROM (
             SELECT r.Numer, r.NazwaPodmiotu, r.DataOperacji, r.OpisOperacji, r.KwotaOperacji, r.SaldoOperacji
             FROM #Rows r
             EXCEPT
             SELECT w.Numer, w.NazwaPodmiotu, w.DataOperacji, w.OpisOperacji, w.KwotaOperacji, w.SaldoOperacji
             FROM WyciagWiersz w
         ) AS ur

    IF (SELECT COUNT(ur.Numer) FROM #UniqueRows ur) > 0
    begin
        INSERT INTO WyciagWiersz(NaglowekId, DataOperacji, NazwaPodmiotu, OpisOperacji, KwotaOperacji, SaldoOperacji, Numer)
        SELECT n.Id, r.DataOperacji, r.NazwaPodmiotu, r.OpisOperacji, r.KwotaOperacji, r.SaldoOperacji, r.Numer FROm #Rows r
        JOIN Naglowek n on r.Numer = n.Numer
    end

    COMMIT TRANSACTION
GO

EXEC InsertData