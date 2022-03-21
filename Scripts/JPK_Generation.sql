USE MS_Business_Intelligence
GO

IF NOT EXISTS(SELECT 1
              FROM sys.objects o
              WHERE o.name = 'JPK_WB_3'
                AND OBJECTPROPERTY(o.object_id, 'IsProcedure') = 1)
    BEGIN
        EXEC sp_sqlexec N'CREATE PROCEDURE dbo.JPK_WB_3 AS '
    END
GO

ALTER PROCEDURE JPK_WB_3(@dataOd date, @dataDo date, @NIP nvarchar(20))
AS
    IF OBJECT_ID('tempdb..#SelectedHeader') IS NOT NULL
        drop table #SelectedHeader

    SELECT n.DataOd
    , n.DataDo
    , n.KodUrzedu
    , n.SaldoPoczatkowe
    , n.SaldoKoncowe
    , n.Numer
    , p.NIP
    INTO #SelectedHeader
    FROM Naglowek n
    JOIN Podmiot p on n.Podmiot = p.Id
    WHERE p.NIP = @NIP
    AND n.DataOd = @dataOd
    AND n.DataDo = @dataDo

    IF OBJECT_ID('tempdb..#SelectedRow') IS NOT NULL
        drop table #SelectedRow

    CREATE TABLE #SelectedRow
    (
        NumerWiersza int,
        DataOperacji date,
        NazwaPodmiotu nvarchar(100),
        OpisOperacji nvarchar(256),
        KwotaOperacji decimal(18,2),
        SaldoOperacji decimal(18,2)
    );

    DECLARE @numerWiersza int = 1,
            @dataOperacji date,
            @nazwaPodmiotu nvarchar(100),
            @opisOperacji nvarchar(256),
            @kwotaOperacji decimal(18,2),
            @saldoOperacji decimal(18,2);

    DECLARE CC INSENSITIVE CURSOR FOR
			SELECT w.DataOperacji
            , w.NazwaPodmiotu
            , w.OpisOperacji
            , w.KwotaOperacji
            , w.SaldoOperacji
            FROM WyciagWiersz w
            JOIN #SelectedHeader h on h.Numer = w.Numer

	OPEN CC
	FETCH NEXT FROM CC INTO @dataOperacji, @nazwaPodmiotu, @opisOperacji, @kwotaOperacji, @saldoOperacji

	WHILE (@@FETCH_STATUS = 0)
	BEGIN
        INSERT INTO #SelectedRow (NumerWiersza, DataOperacji, NazwaPodmiotu, OpisOperacji, KwotaOperacji, SaldoOperacji)
        VALUES (@numerWiersza, @dataOperacji, @nazwaPodmiotu, @opisOperacji, @kwotaOperacji, @saldoOperacji)

        SET @numerWiersza = @numerWiersza + 1
		FETCH NEXT FROM CC INTO @dataOperacji, @nazwaPodmiotu, @opisOperacji, @kwotaOperacji, @saldoOperacji
	END
	CLOSE CC
	DEALLOCATE CC

    declare @xml xml
    SET @xml = null;

    WITH XMLNAMESPACES(N'http://jpk.mf.gov.pl/wzor/2019/09/27/09271/'AS tns
    , N'http://crd.gov.pl/xml/schematy/dziedzinowe/mf/2018/08/24/eD/DefinicjeTypy/' AS etd)
    select @xml =
    ( SELECT
        ( SELECT
            N'1-0' AS [tns:KodFormularza/@wersjaSchemy]
          , N'JPK_WB (1)' AS [tns:KodFormularza/@kodSystemowy]
          , N'JPK_WB' AS [tns:KodFormularza]
          , N'1' AS [tns:WariantFormularza]
          , N'1' AS [tns:CelZlozenia]
          , GETDATE() AS [tns:DataWytworzeniaJPK]
          , @dataOd AS [tns:DataOd]
          , @dataDo AS [tns:DataDo]
          , N'PLN' AS [tns:DomyslnyKodWaluty]
          , h.KodUrzedu AS [tns:KodUrzedu]
            FROM #SelectedHeader h
            FOR XML PATH('tns:Naglowek'), TYPE),
        ( SELECT
            ( SELECT p.NIP AS [etd:NIP]
                , p.Nazwa AS [etd:PelnaNazwa]
                FROM Podmiot p WHERE p.NIP = @NIP
                FOR XML PATH('tns:IdentyfikatorPodmiotu'), TYPE),
            ( SELECT p.KodKraju AS [etd:KodKraju]
                , p.Woj AS [etd:Wojewodztwo]
                , p.Powiat AS [etd:Powiat]
                , p.Gmina AS [etd:Gmina]
                , p.Ulica AS [etd:Ulica]
                , p.Numer AS [etd:NrDomu]
                , 'brak' AS [etd:NrLokalu]
                , p.Miasto AS [etd:Miejscowosc]
                , p.KodPocztowy AS [etd:KodPocztowy]
                , p.Poczta AS [etd:Poczta]
                FROM Podmiot p WHERE p.NIP = @NIP
                FOR XML PATH('tns:AdresPodmiotu'), TYPE)
             FOR XML PATH('tns:Podmiot1'), TYPE),
        ( SELECT r.Numer AS [etd:NumerRachunku]
            FROM RachunekBankowy r
            JOIN Podmiot p on r.Id = p.RachunekBankowy
            WHERE p.NIP = @NIP
            FOR XML PATH('tns:NumerRachunku'), TYPE),
        ( SELECT h.SaldoPoczatkowe AS [etd:SaldoPoczatkowe]
            , h.SaldoKoncowe AS [etd:SaldoKoncowe]
            FROM #SelectedHeader h
            FOR XML PATH('tns:Salda'), TYPE),
        ( SELECT r.NumerWiersza AS [etd:NumerWiersza]
            , r.DataOperacji AS [etd:DataOperacji]
            , r.NazwaPodmiotu AS [etd:NazwaPodmiotu]
            , r.OpisOperacji AS [etd:OpisOperacji]
            , r.KwotaOperacji AS [etd:KwotaOperacji]
            , r.SaldoOperacji AS [etd:SaldoOperacji]
            FROM #SelectedRow r
            FOR XML PATH('tns:WyciagWiersz'), TYPE),
        ( SELECT COUNT(r.NumerWiersza) AS [etd:LiczbaWierszy],
            ABS(SUM(IIF(r.KwotaOperacji < 0, r.KwotaOperacji, 0))) AS [etd:SumaObciazen],
            ABS(SUM(IIF(r.KwotaOperacji > 0, r.KwotaOperacji, 0))) AS [etd:SumaUznan]
            FROM #SelectedRow r
            FOR XML PATH('WyciagCtrl'), TYPE)
        FOR XML PATH(''), TYPE, ROOT('tns:JPK')
    )

    SELECT @xml;
GO

EXEC dbo.JPK_WB_3 '2022-01-01', '2022-01-31', '1054567898'