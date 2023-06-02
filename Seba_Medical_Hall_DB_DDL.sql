
-------------Create Database 
USE master
GO
	IF DB_ID('SebaMedicalHall_DB') is not null --- Code if database object Exists
		DROP DATABASE SebaMedicalHall_DB
GO
DECLARE @data_path nvarchar(256);
SET @data_path = (SELECT SUBSTRING(physical_name, 1, CHARINDEX(N'master.mdf', LOWER(physical_name)) - 1)
      FROM master.sys.master_files
      WHERE database_id = 1 AND file_id = 1);
EXECUTE ('CREATE DATABASE SebaMedicalHall_DB
ON PRIMARY(NAME = SebaMedicalHall_DB_data, FILENAME = ''' + @data_path + 'SebaMedicalHall_DB_data.mdf'', SIZE = 20MB, MAXSIZE = Unlimited, FILEGROWTH = 5MB)
LOG ON (NAME = SebaMedicalHall_DB_log, FILENAME = ''' + @data_path + 'SebaMedicalHall_DB_log.ldf'', SIZE = 10MB, MAXSIZE = 200MB, FILEGROWTH = 1MB)'
);
GO

Use SebaMedicalHall_DB
Go
------Create Schema name

Create Schema ih
Go

IF OBJECT_ID('PatientAdmit') is not null -- if table is exist
	DROP TABLE PatientAdmit
go

---------------Create Table
Create Table ih.Department
(
	DepartmentID Int Primary Key Identity(1,1),
	DepartmentName Varchar(20) Not Null,
	AvailableSeat int Not Null
)
Go

Create Table Doctor 
(
	DoctorID Int Primary key,
	DoctorFName varchar (10) Not Null,
	DoctorLName varchar (10) Not Null,
	ContactAddress varchar(25) Sparse Null,
	CellPhoneNo varchar(15) Unique Check (CellPhoneNo like '018%' or CellPhoneNo like '017%' or CellPhoneNo like '016%' or CellPhoneNo like '019%' or CellPhoneNo like '015%'),
	Salary Decimal (10,2),
	DepartmentID int Foreign key References ih.Department(DepartmentID) on update cascade on Delete cascade
)
Go

Create Table PatientAdmit
(
	PatientID Int Primary key Identity,
	PatientName varchar(20) Not Null,
	PatientAddress Varchar (20) Not Null,
	Contact char(16) Check(Contact like '[0][1][0-9][0-9][0-9] [0-9][0-9][0-9] [0-9][0-9][0-9]'),
	AdmissionFee Decimal(10,2),
	AdmitDate Date Default(Sysdatetime()),
	DepartmentID int Foreign Key references ih.Department (DepartmentID) ,
	DoctorID int Foreign Key references Doctor (DoctorID)
)
Go

Create Table PatientRelease
(
	ID int Primary Key Identity,
	TotalBill Decimal (10,2),
	ReleaseDate Datetime Default(Getdate()),
	PatientID int Foreign Key References PatientAdmit(PatientID) on update cascade on delete cascade,
	Discountrate Decimal (10,2),
	DiscountAmount Decimal (10,2),
	NetBill as (TotalBill-DiscountAmount)
)
go

------------Create Function (Scalar) For Calculation of Discount Amount

Create Function fn_Discount(@totalbill decimal(10,2),@discountrate decimal(10,2))
	Returns Decimal 
As
Begin
	Declare @discountamount decimal (10,2)
		Set @discountamount=@totalbill*@discountrate
	Return @discountamount
End
Go

------Create Tabular Function 

Create Function fn_DoctorID(@doctorid int)
	Returns Table
As
Return	(Select DoctorID,DoctorFName,DoctorLName,CellphoneNo  
		From Doctor
		Where DoctorID=@doctorid)

Go

Select * from dbo.fn_doctorid(2)

---------------Create Sequence For Doctor Table

USE SebaMedicalHall_DB
Create SEQUENCE seq_doctors
	AS Bigint
	START WITH 1
	INCREMENT BY 1
GO
--drop sequence seq_doctors

------------Create Store Procedure to Insert data in PatientAdmit Within Update Data to Department table

Create PROC sp_AdmitInsert
	@patientid int,
	@patientname varchar(20),
	@patientaddress varchar (20),
	@contact char(16),
	@admissionfee decimal(10,2),
	@admitdate date,
	@departmentid int,
	@doctorid int

As
Begin
	Insert Into PatientAdmit values(@patientname,@patientaddress,@contact,@admissionfee,@admitdate,@departmentid,@doctorid)
	Update ih.Department Set AvailableSeat=AvailableSeat-1
	Where DepartmentID=@departmentid
End
go

------------Create Store Procedure to Insert data in PatientRelease Within Update Data to Department table

Create PROC sp_ReleaseInsert
	@id int,
	@totalBill Decimal (10,2),
	@releaseDate Datetime2,
	@patientid int,
	@departmentid int,
	@discountrate Decimal (10,2)
As
Begin
	Begin Tran
		Insert into PatientRelease Values (@totalBill,@releaseDate,@patientid,@discountrate,dbo.fn_discount(@totalBill,@discountrate))

		update ih.Department Set Availableseat=Availableseat+1
		Where DepartmentID=@departmentid
	Commit Tran
End
Go

----------Create View with Encryption

Create View vw_Service
With Encryption
As
(
Select Distinct DepartmentName, AvailableSeat, DoctorFName, DoctorLName, cellPhoneNo
From ih.Department
join Doctor
On Doctor.DepartmentID=Department.DepartmentID
)
Go

--------Create table For Trigger

Create Table PatientAdmitAction
(PatientID Int,
PatientName varchar(20) Not Null,
PatientAddress Varchar (20) Not Null,
Contact char(16) Check(Contact like '[0][1][0-9][0-9][0-9] [0-9][0-9][0-9] [0-9][0-9][0-9]'),
AdmissionFee Decimal(10,2),
AdmitDate Date Default(Sysdatetime()),
DepartmentID int,
DoctorID int,
ActionType Varchar (50),
ActionTime Datetime Default(Sysdatetime())
)
Go

-------------Create Trigger (Instead Of Insert) For PatientAdmit Table

Create Trigger tri_InsteadOfInsert on dbo.PatientAdmit
Instead Of Insert
As
	Declare
		@patientid int,
		@patientname varchar(20),
		@patientaddress varchar (20),
		@contact char(16),
		@admissionfee decimal(10,2),
		@admitdate date,
		@departmentid int,
		@doctorid int,
		@actiontype  varchar(50),
		@actiontime datetime

	Select @patientid=i.PatientID From Inserted i
	Select @patientname=i.PatientName From Inserted i
	Select @patientaddress=i.PatientAddress From Inserted i
	Select @contact=i.Contact From Inserted i
	Select @admissionfee=i.AdmissionFee From Inserted i
	Select @admitdate=i.AdmitDate From Inserted i
	Select @departmentid=i.DepartmentID From Inserted i
	Select @doctorid=i.DoctorID From Inserted i
	Set @actiontype='Instead of Insert Trigger Fired !!!'

Begin
	Begin tran
		If 
			@admissionfee<100
			Begin
				Raiserror('Sorry...You Need To Pay Minimum Fee',16,1)
				RollBack
			End

		Else
			Begin
				Insert Into PatientAdmit (PatientName,PatientAddress,Contact,AdmissionFee,Admitdate,DepartmentID,DoctorID)  
					values (@patientname,@patientaddress,@contact,@admissionfee,@admitdate,@departmentid,@doctorid)

				Insert into PatientAdmitAction(PatientID,PatientName,PatientAddress,Contact,AdmissionFee,Admitdate,DepartmentID,DoctorID,ActionType,ActionTime)
					values(@@IDENTITY,@patientname,@patientaddress,@contact,@admissionfee,@admitdate ,@departmentid,@doctorid,@actiontype,sysdatetime())
			End
	Commit tran

	Print  'Patient Admitted SuccessFully :' +''+ Cast(Sysdatetime() as varchar) 
End
Go


-------------Create Trigger (Instead Of Update) For PatientAdmit table

Create Trigger tri_InsteadOfUpdate on dbo.PatientAdmit
Instead Of Update
As
	Declare
		@patientid int,
		@patientname varchar(20),
		@patientaddress varchar (20),
		@contact char(16),
		@admissionfee decimal(10,2),
		@admitdate date,
		@departmentid int,
		@doctorid int,
		@actiontype  varchar(50),
		@actiontime datetime

	Select @patientid=u.PatientID From Inserted u
	Select @patientname=u.PatientName From Inserted u
	Select @patientaddress=u.PatientAddress From Inserted u
	Select @contact=u.Contact From Inserted u
	Select @admissionfee=u.AdmissionFee From Inserted u
	Select @admitdate=u.AdmitDate From Inserted u
	Select @departmentid=u.DepartmentID From Inserted u
	Select @doctorid=u.DoctorID From Inserted u
	Set @actiontype='Instead of Update Trigger Fired !!!'

Begin
	Update PatientAdmit Set PatientName=@patientname,PatientAddress=@patientaddress,Contact=@contact,AdmissionFee=@admissionfee,
	Admitdate=@admitdate,DepartmentID=@departmentid,DoctorID=@doctorid
		Where PatientID=@patientid
	

	Insert into PatientAdmitAction(PatientID,PatientName,PatientAddress,Contact,AdmissionFee,Admitdate,DepartmentID,DoctorID,ActionType,ActionTime)
		values(@@IDENTITY,@patientname,@patientaddress,@contact,@admissionfee,@admitdate ,@departmentid,@doctorid,@actiontype,sysdatetime())

	Print 'Information updated Successfully '
End
Go


-------------Create Trigger (Instead Of Delete) For PatientAdmit Table

Create Trigger tri_InsteadOfDelete on dbo.PatientAdmit
Instead Of Delete
As
	Declare
		@patientid int,
		@patientname varchar(20),
		@patientaddress varchar (20),
		@contact char(16),
		@admissionfee decimal(10,2),
		@admitdate date,
		@departmentid int,
		@doctorid int,
		@actiontype  varchar(50),
		@actiontime datetime

	Select @patientid=d.PatientID From Deleted d
	Select @patientname=d.PatientName From Deleted d
	Select @patientaddress=d.PatientAddress From Deleted d
	Select @contact=d.Contact From Deleted d
	Select @admissionfee=d.AdmissionFee From Deleted d
	Select @admitdate=d.AdmitDate From Deleted d
	Select @departmentid=d.DepartmentID From Deleted d
	Select @doctorid=d.DoctorID From Deleted d
	Set @actiontype='Instead of Delete Trigger Fired !!!'

Begin
	Begin tran
		Begin
			Delete From PatientAdmit
				Where PatientID=@patientid
	

			Insert into PatientAdmitAction(PatientID,PatientName,PatientAddress,Contact,AdmissionFee,Admitdate,DepartmentID,DoctorID,ActionType,ActionTime)
				values(@@IDENTITY,@patientname,@patientaddress,@contact,@admissionfee,@admitdate ,@departmentid,@doctorid,@actiontype,sysdatetime())
		End
	Commit tran

	Print 'Information Deleted Successfully '
End
Go

--------Create Table For After Trigger 

Create Table PatientReleaseAction
(
	ID int,
	TotalBill Decimal (10,2),
	ReleaseDate Datetime Default(Getdate()),
	PatientID int,
	Discountrate Decimal (10,2),
	ActionType Varchar (40),
	ActionTime Datetime Default(Sysdatetime())
)
go

-------------Create Insert Trigger (After/For) For PatientRelease table

Create Trigger tri_Insert on dbo.PatientRelease
For Insert
As
	Declare 

		@id int,
		@totalBill Decimal (10,2),
		@releaseDate Datetime2,
		@patientid int,
		@discountrate Decimal (10,2),
		@actiontype  varchar,
		@actiontime datetime

	Select @id=i.ID From Inserted i
	Select @totalbill=i.TotalBill From Inserted i
	Select @releaseDate=i.ReleaseDate From Inserted i
	Select @patientid=i.PatientID From Inserted i
	Select @discountrate=i.DiscountRate From Inserted i
	Set @actiontype='After Insert Trigger Fired !!!'

Begin
	Insert into PatientReleaseAction(ID,TotalBill,ReleaseDate,PatientID,Discountrate,ActionType,ActionTime) 
		Values (@@Identity,@totalbill,@releaseDate,@patientid,@discountrate,@actiontype,sysdatetime())
End
Go

-------------Create Update Trigger (After/For) For PatientRelease table

Create Trigger tri_Update on dbo.PatientRelease
For Update
As
	Declare 
		@id int,
		@totalBill Decimal (10,2),
		@releaseDate Datetime2,
		@patientid int,
		@discountrate Decimal (10,2),
		@actiontype  varchar,
		@actiontime datetime

	Select @id=i.ID From Inserted i
	Select @totalbill=i.TotalBill From Inserted i
	Select @releaseDate=i.ReleaseDate From Inserted i
	Select @patientid=i.PatientID From Inserted i
	Select @discountrate=i.DiscountRate From Inserted i
	Set @actiontype='After Update Trigger Fired !!!'

Begin
	Insert into PatientReleaseAction(ID,TotalBill,ReleaseDate,PatientID,Discountrate,ActionType,ActionTime) 
		Values (@@Identity,@totalbill,@releaseDate,@patientid,@discountrate,@actiontype,sysdatetime())

	Print 'Information Updated Sucessfully'
End
Go

-------------Create Delete Trigger (After/For) For PatientRelease table

Create Trigger tri_Delete on dbo.PatientRelease
For Delete
As
	Declare 
		@id int,
		@totalBill Decimal (10,2),
		@releaseDate Datetime2,
		@patientid int,
		@discountrate Decimal (10,2),
		@actiontype  varchar,
		@actiontime datetime

	Select @id=i.ID From Deleted i
	Select @totalbill=i.TotalBill From Deleted i
	Select @releaseDate=i.ReleaseDate From Deleted i
	Select @patientid=i.PatientID From Deleted i
	Select @discountrate=i.DiscountRate From Deleted i
	Set @actiontype='After Delete Trigger Fired !!!'

Begin
	Insert into PatientReleaseAction(ID,TotalBill,ReleaseDate,PatientID,Discountrate,ActionType,ActionTime) 
		Values (@@Identity,@totalbill,@releaseDate,@patientid,@discountrate,@actiontype,sysdatetime())

	 print 'Information Deleted SuccessFully'
End
Go


------Create Table For Merge,Union, Index,Alter Column

Create Table Employee
(
	EmployeeID int,
	Employeename varchar (20),
	ContactAddress Varchar (25),
	Salary money
)
go

Create Table Employee_tmp
(	EmployeeID int,
	Employeename varchar (20),
	ContactAddress Varchar (25),
	Salary money
)
Go

Create table Nurse 
(
	NurseID int,
	Nursename varchar (20),
	ContactAddress Varchar (25),
	Salary money 
)
Go

-------------Create Temporary table & variable temporary table

--Local Temporary table

Create table #Doctors 
(
	Id Int,
	DoctorName varchar (20),
	ContactInfo Varchar (25)
)
Go

--Global teporary table 

Create Table ##Departments 
(
	ID Int,
	DepartName Varchar (15),
	AvaialableSeat Int
)
go


Declare @Nurse table
(
	NurseID int,
	NurseName Varchar (10),
	ContactAddress Varchar(15),
	Salary Money
)
Insert into @Nurse Values (1,'Faiyza','jamalpur',10000)
Select * From @Nurse



-----Index

Create Clustered Index clusindex
on Employee(EmployeeID)

Create Nonclustered Index ncluindex
on ih.Department(Departmentname)



----Alter Column

Alter Table Employee
Add Cellphone Varchar(15) 
Go

----Drop Column

Alter table Employee
Drop Column Cellphone
Go

select * from PatientAdmit
select * from ih.Department