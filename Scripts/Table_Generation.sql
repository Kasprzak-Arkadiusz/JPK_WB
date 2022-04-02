create table LOG
(
    Id              int identity
        constraint LOG_pk
            primary key,
    OpisBledu       nvarchar(256) not null,
    DataWystapienia datetime,
    KodBledu        nvarchar(20)  not null
)
go

create unique index LOG_Id_uindex
    on LOG (Id)
go

create table Naglowek_imp_tmp
(
    Id              int identity
        constraint Naglowek_tmp_imp_pk
            primary key,
    DataOd          nvarchar(10),
    DataDo          nvarchar(10)  not null,
    KodUrzedu       nchar(4)      not null,
    Numer           int           not null,
    NIP             nvarchar(20)  not null,
    NazwaPodmiotu   nvarchar(100) not null,
    KodKraju        nchar(2)      not null,
    Woj             nvarchar(40)  not null,
    Powiat          nvarchar(40)  not null,
    Gmina           nvarchar(40)  not null,
    Ulica           nvarchar(40)  not null,
    NumerDomu       nvarchar(5)   not null,
    Miasto          nvarchar(40)  not null,
    KodPocztowy     nchar(6)      not null,
    Poczta          nvarchar(40)  not null,
    NumerRachunku   nvarchar(34)  not null,
    SaldoPoczatkowe nvarchar(20)  not null,
    SaldoKoncowe    nvarchar(20)  not null
)
go

create unique index Naglowek_tmp_imp_Id_uindex
    on Naglowek_imp_tmp (Id)
go

create table RachunekBankowy
(
    Id    int identity
        constraint RachunekBankowy_pk
            primary key,
    Numer varchar(34) not null
)
go

create table Podmiot
(
    Id              int identity
        constraint Podmiot_pk
            primary key,
    Nazwa           nvarchar(100) not null,
    KodKraju        nchar(2)      not null,
    Woj             nvarchar(40)  not null,
    Powiat          nvarchar(40)  not null,
    Gmina           nvarchar(40)  not null,
    Miasto          nvarchar(40)  not null,
    Ulica           nvarchar(40)  not null,
    Numer           nvarchar(5)   not null,
    NIP             nvarchar(20)  not null,
    KodPocztowy     nchar(6)      not null,
    Poczta          nvarchar(40)  not null,
    RachunekBankowy int
        constraint Podmiot_RachunekBankowy_fk
            references RachunekBankowy
)
go

exec sp_addextendedproperty 'MS_Description', N'Pełna nazwa', 'SCHEMA', 'dbo', 'TABLE', 'Podmiot', 'COLUMN', 'Nazwa'
go

exec sp_addextendedproperty 'MS_Description', N'Numer domu oraz numer lokalu są uznawane za tożsame', 'SCHEMA', 'dbo',
     'TABLE', 'Podmiot', 'COLUMN', 'Numer'
go

exec sp_addextendedproperty 'MS_Description', N'Miejscowość w której znajduje sie urzęd pocztowy', 'SCHEMA', 'dbo',
     'TABLE', 'Podmiot', 'COLUMN', 'Poczta'
go

create table Naglowek
(
    Id              int identity
        constraint Naglowek_pk
            primary key,
    DataOd          date           not null,
    DataDo          date           not null,
    KodUrzedu       nchar(4)       not null,
    Podmiot         int
        constraint Naglowek_Podmiot_fk
            references Podmiot,
    SaldoPoczatkowe decimal(18, 2) not null,
    SaldoKoncowe    decimal(18, 2) not null,
    Numer           int            not null
)
go

create unique index Naglowek_Id_uindex
    on Naglowek (Id)
go

create unique index Naglowek_Numer_uindex
    on Naglowek (Numer)
go

create unique index Podmiot_NIP_uindex
    on Podmiot (NIP)
go

create unique index RachunekBankowy_Id_uindex
    on RachunekBankowy (Id)
go

create unique index RachunekBankowy_Numer_uindex
    on RachunekBankowy (Numer)
go

create table WyciagWiersz
(
    NaglowekId    int            not null
        constraint WyciagWiersz_Naglowek_fk
            references Naglowek,
    DataOperacji  date           not null,
    NazwaPodmiotu nvarchar(256)  not null,
    OpisOperacji  nvarchar(256)  not null,
    KwotaOperacji decimal(18, 2) not null,
    SaldoOperacji decimal(18, 2) not null,
    Numer         int            not null,
    Id            int identity
        constraint WyciagWiersz_pk
            primary key
)
go

exec sp_addextendedproperty 'MS_Description', N'Nazwa podmiotu będącego stroną operacji', 'SCHEMA', 'dbo', 'TABLE',
     'WyciagWiersz', 'COLUMN', 'NazwaPodmiotu'
go

create unique index WyciagWiersz_Id_uindex
    on WyciagWiersz (Id)
go

create table WyciagWiersz_imp_tmp
(
    NumerWiersza  int           not null,
    DataOperacji  nvarchar(10)  not null,
    NazwaPodmiotu nvarchar(256) not null,
    OpisOperacji  nvarchar(256) not null,
    KwotaOperacji nvarchar(20)  not null,
    SaldoOperacji nvarchar(256) not null,
    Numer         int           not null,
    Id            int identity
        constraint WyciagWiersz_imp_tmp_pk
            primary key
)
go

create unique index WyciagWiersz_imp_tmp_Id_uindex
    on WyciagWiersz_imp_tmp (Id)
go

