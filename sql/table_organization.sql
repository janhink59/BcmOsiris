if object_id('organization') is null
begin
	create table organization(
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
		-- specific organization columns
		---------------------------------------
		note varchar(max) default '' not null,
		login_disabled bit default 0 not null,
		login_domain varchar(200) default '' not null,
		licence_level tinyint default 0 not null,
		register_id bigint default 0 null,
		tax_id varchar(40) default '' not null,
		invoice_info varchar(max) default '' not null,
		
		-- address
		address_name varchar(100) default '' not null,
		address_street varchar(100) default '' not null,
		address_city varchar(100) default '' not null,
		address_zip varchar(10) default '' not null,
		address_state varchar(40) default '' not null,
		www_address varchar(200) default '' not null,

		-- logo media
		logo_data varbinary(max) null,
		logo_filename varchar(255) default '' not null,
		logo_mime_type varchar(100) default '' not null,

		constraint pk_organization primary key (uuid)
	)
end
go

---------------------------------------
-- Indexes for RAC architecture
---------------------------------------

-- Unique active record per owner/original
if not exists (select 1 from sys.indexes where name = 'uq_organization_active' and object_id = object_id('organization'))
begin
	create unique index uq_organization_active 
		on organization(original, object_owner) 
		where record_type = 'A'
end
go

-- Unique language version per owner/original/language
if not exists (select 1 from sys.indexes where name = 'uq_organization_language' and object_id = object_id('organization'))
begin
	create unique index uq_organization_language 
		on organization(original, object_owner, language) 
		where record_type = 'L'
end
go

---------------------------------------
-- Seed: System Organization (0x00)
---------------------------------------

if not exists (select 1 from organization where original = 0x00000000000000000000000000000000 and record_type = 'A')
begin
	insert into organization (
		uuid,
		object_owner,
		original,
		record_type,
		approval_status,
		caption,
		shortname,
		description_text
	)
	values (
		0x00000000000000000000000000000000,
		0x00000000000000000000000000000000,
		0x00000000000000000000000000000000,
		'A',
		'A',
		'System',
		'SYS',
		'System master organization'
	)
end
go
