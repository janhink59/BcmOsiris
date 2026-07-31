--------------------------------------------------------------------------------
-- Tabulka: user_account
-- Popis:   Evidence uživatelských úètù s podporou multi-tenancy, RAC a SSC
--------------------------------------------------------------------------------

if object_id('user_account') is null
begin
	create table user_account(
		---------------------------------------
		-- standard RAC & SSC columns
		---------------------------------------
		uuid uuid not null,
		object_owner uuid default 0x00 not null,
		original uuid default 0x00 not null,
		record_type varchar(1) default 'A' not null,
		approval_status varchar(1) default 'A' not null,
		inactive bit default 0 not null,
		removed bit default 0 not null,
		language varchar(2) default 'en' not null,
		valid_from date default '1970-01-01' not null,
		valid_to date null,
		is_template bit default 0 not null,
		template uuid null,
		caption varchar(200) default '' not null,
		shortname varchar(40) default '' not null,
		external_code varchar(200) default '' not null,
		instance_class_name varchar(80) default '' not null,
		description_text varchar(max) default '' not null,
		help_text varchar(max) default '' not null,
		date_created datetime default getdate() not null,
		who_created uuid default 0x00 not null,
		date_modified datetime default getdate() not null,
		who_modified uuid default 0x00 not null,

		---------------------------------------
		-- specific user_account columns
		---------------------------------------
		-- Authentication & Identity
		login_name varchar(100) default '' not null,
		email varchar(200) default '' not null,
		password_hash varchar(255) default '' not null,
		user_title_before varchar(40) default '' not null,
		first_name varchar(100) default '' not null,
		last_name varchar(100) default '' not null,
		user_title_after varchar(40) default '' not null,
		phone varchar(50) default '' not null,
		mobile varchar(50) default '' not null,
		
		-- Organization & Department structure
		department_name varchar(150) default '' not null,
		job_title varchar(150) default '' not null,
		manager_uuid uuid null,

		-- Security & Auth properties
		is_system_admin bit default 0 not null,
		require_password_change bit default 0 not null,
		failed_login_attempts int default 0 not null,
		locked_until datetime null,
		last_login_date datetime null,
		last_password_change datetime null,
		mfa_enabled bit default 0 not null,
		mfa_secret varchar(100) default '' not null,
		note varchar(max) default '' not null,

		constraint pk_user_account primary key (uuid)
	)
end
go

---------------------------------------
-- Indexes for RAC architecture
---------------------------------------

-- Unique active record per owner/original
if not exists (select 1 from sys.indexes where name = 'uq_user_account_active' and object_id = object_id('user_account'))
begin
	create unique index uq_user_account_active 
		on user_account(original, object_owner) 
		where record_type = 'A'
end
go

-- Unique language version per owner/original/language
if not exists (select 1 from sys.indexes where name = 'uq_user_account_language' and object_id = object_id('user_account'))
begin
	create unique index uq_user_account_language 
		on user_account(original, object_owner, language) 
		where record_type = 'L'
end
go

-- Unique active login_name per object_owner
if not exists (select 1 from sys.indexes where name = 'uq_user_account_login' and object_id = object_id('user_account'))
begin
	create unique index uq_user_account_login 
		on user_account(login_name, object_owner) 
		where record_type = 'A' and inactive = 0 and removed = 0
end
go

---------------------------------------
-- Seed: System User Account (0x00)
---------------------------------------

if not exists (select 1 from user_account where original = 0x00000000000000000000000000000000 and record_type = 'A')
begin
	insert into user_account (
		uuid,
		object_owner,
		original,
		record_type,
		approval_status,
		caption,
		shortname,
		description_text,
		login_name,
		email,
		first_name,
		last_name,
		is_system_admin
	)
	values (
		0x00000000000000000000000000000000,
		0x00000000000000000000000000000000,
		0x00000000000000000000000000000000,
		'A',
		'A',
		'System Administrator',
		'admin',
		'System master user account',
		'system',
		'system@localhost',
		'System',
		'Administrator',
		1
	)
end
go