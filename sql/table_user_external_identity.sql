-- Upozornìní: Pøíkaz DROP TABLE IF EXISTS vyžaduje SQL Server 2016 a novìjší.
-- Zpìtná kompatibilita DB CL110 se zde nevyžaduje[cite: 1].
DROP TABLE IF EXISTS [dbo].[user_external_identity];
GO

CREATE TABLE [dbo].[user_external_identity] (
	-- 1. RAC (Record & Access Control) sloupce
	[uuid] uniqueidentifier NOT NULL,
	[original] uniqueidentifier NOT NULL,
	[object_owner] uniqueidentifier NOT NULL,
	[record_type] varchar(1) NOT NULL,

	-- 2. SSC (Schvalovací cyklus) a stavy
	[approval_status] varchar(1) NOT NULL,
	[inactive] bit NOT NULL CONSTRAINT [DF_user_external_identity_inactive] DEFAULT (0),
	[removed] bit NOT NULL CONSTRAINT [DF_user_external_identity_removed] DEFAULT (0),

	-- 3. Specifické byznys sloupce pro externí identitu (SSO/IdP)
	[provider_name] varchar(50) NOT NULL,
	[provider_user_id] varchar(255) NOT NULL,
	[user_account] uniqueidentifier NOT NULL,

	-- 4. Povinné auditní a sledovací sloupce
	[date_created] datetime2(7) NOT NULL,
	[who_created] uniqueidentifier NOT NULL,
	[date_modified] datetime2(7) NOT NULL,
	[who_modified] uniqueidentifier NOT NULL,
	[valid_from] datetime2(7) NOT NULL,
	[valid_to] datetime2(7) NOT NULL,
	[language] varchar(2) NOT NULL,

	-- Primární klíè na úrovni databázového øádku
	CONSTRAINT [PK_user_external_identity] PRIMARY KEY CLUSTERED ([uuid] ASC)
);
GO

-- Indexy pro zrychlení vyhledávání bìžných dotazù
CREATE NONCLUSTERED INDEX [IX_user_external_identity_provider] 
	ON [dbo].[user_external_identity] ([provider_name], [provider_user_id], [record_type]);
GO

CREATE NONCLUSTERED INDEX [IX_user_external_identity_user] 
	ON [dbo].[user_external_identity] ([user_account_original], [record_type]);
GO
