USE	SabaDB;
GO
EXECUTE	dbo.sp_MSR_CreateUser 'sqlLink';
EXECUTE	dbo.sp_MSR_CreateUser 'lmnGrafana';
EXECUTE	dbo.sp_MSR_CreateUser 'lmnBackend';

GO