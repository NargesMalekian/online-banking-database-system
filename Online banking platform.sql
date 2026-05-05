
--------------------------------------------------------------------------------
--Creating Database
--------------------------------------------------------------------------------

create database  ADB_Banking_Platform
go


--------------------------------------------------------------------------------------------------------
----create table customer
---------------------------------------------------------------------------------------------------------

use ADB_Banking_Platform
go
create table Customers(
  CustomerId int identity(1,1) primary key,
  FirstName nvarchar(30) not null,
  LastName nvarchar(60) not null,
  DateOfBirth date not null, constraint check (DateOfBirth<='2008-04-27'),  --Check If the customer is over 18 or not

  UserName nvarchar(20) unique not null check ( UserName NOT LIKE '%[^a-zA-Z]%'), --username must be only alphabet
  Password varbinary(256) not null, -- I tested sting before but for security it is better now
  Email nvarchar(50) unique null check (Email like '%@%.%'),  --validation emails
  MobilePhone varchar(15) unique null check ( 
    LEN(MobilePhone) >= 10      --checking lenghth of mobilephones
    AND MobilePhone not like '%[^0-9]%'
),
  AddressLine1 nvarchar(100) not null,
  AddressLine2 nvarchar(100) null,        --Address could be stored on extra table, but I want to create tables as question want 
  City nvarchar (50) not null,
  PostCode nvarchar(15) not null check (len (PostCode) >=5)
  );

-------------------------------------------------------------------------------------------------
--Creating table Accounts
 ------------------------------------------------------------------------------------------------

 use ADB_Banking_Platform
  go
  create table Accounts(
  AccountID int identity(1,1) not null primary key,
  CustomerID int not null FOREIGN KEY 
        REFERENCES Customers(CustomerID),
  AccountType nvarchar(20) NOT NULL CHECK (AccountType IN ( 'Savings','Checking', 'Loan','Credit Card','Investment'
)),
AccountName nvarchar(100) not null,
AccountOpeningDate date not null,
status nvarchar(20) not null check (status in ('active','closed','frozen','dormant')),
AccountCloseDate date null,  --this should be must for account which has been closed or forzen
AccountFreezeDate date null,
ReferenceNumber VARCHAR(20) UNIQUE NULL, --this reference number should be unique and only must for loans 

constraint Ck_LoanWithReferenceNumber --check if loan account must have reference number
CHECK ((AccountType = 'Loan' AND ReferenceNumber IS NOT NULL)
    OR (AccountType <> 'Loan') ),

constraint Ck_ClosedAccountWithDate --check closed account must have date
 CHECK ( (Status = 'closed' AND AccountCloseDate IS NOT NULL)
    OR (Status <> 'closed')  ),

Constraint Ck_FrozenAccountWithDate --check frozen account must have date
CHECK ((Status = 'frozen' AND AccountFreezeDate IS NOT NULL)
    OR (Status <> 'frozen') ));

--------------------------------------------------------------------------------------------
---Create table Transaction 
---------------------------------------------------------------------------------------------

use ADB_Banking_Platform
  go
 create table Transactions(
 TransactionID int identity(1,1) primary key,
 AccountID int not null foreign key  references Accounts(AccountID),
 TransactionAmount decimal(15,2) not null check(TransactionAmount > 0),
 TransactionType nvarchar(20) not null
        check (TransactionType in ('Deposit','Withdrawal','Transfer','Payment')),
 TransactionStatus nvarchar(20) not null
        check (TransactionStatus in ('Pending','Completed','Failed')),
 TransactionDate datetime2 not null DEFAULT SYSDATETIME(),  --If we don't import date, by default set today
 DueDate date null,
 CompletionDate datetime2 null, --The type of 'datetime2' is more optimism and accurate 

 constraint Ck_CompletedTransaction --It should be considered as data integrity, when transaction completed, should have date
 check(( TransactionStatus = 'Completed' and Completiondate is not null)
 or (transactionStatus in ('Pending','Failed') and CompletionDate is null))
 );

 -------------------------------------------------------------------------------------
 --Create Table OverDueFees
 -------------------------------------------------------------------------------------

 use ADB_Banking_Platform
  go
create table OverdueFees (
    OverdueFeesID int identity(1,1) primary key,
    TransactionID int not null foreign key REFERENCES Transactions(TransactionID),
    DueDate date not null, 
    OverdueDays AS (   --this column will be calculated from duedate automaticly
        CASE 
            WHEN CAST(GETDATE() AS date) > DueDate   --
                THEN DATEDIFF(DAY, DueDate, CAST(GETDATE() AS date))
            ELSE 0
        END),
    OriginalAmount decimal(15,2) not null check (OriginalAmount>0),   -- This is original amount
    AnnualInterestRate decimal(5,2) not null check (AnnualInterestRate >=0),   -- This is interest rate based on year, we use it to calculate FeesAmount based on OverdueDayes                                                                                                       
    OverdueFeesAmount AS (  --this column is calculated from interest rate and overduedays
        OriginalAmount * (AnnualInterestRate / 100.0) / 365 *
        CASE 
            WHEN CAST(GETDATE() AS date) > DueDate 
                THEN DATEDIFF(DAY, DueDate, CAST(GETDATE() AS date))    ---this calculated overduedays between now and due date
            ELSE 0
        END),
    TotalPaid DECIMAL(15,2) NOT NULL DEFAULT 0 CHECK (TotalPaid >= 0),  -- I will insert trigger for here, to calculate totalpaid automaticly based on repayment
    Balance AS (      --balance calculated based on originalamount and total paid.
        OriginalAmount + 
        ( OriginalAmount * (AnnualInterestRate / 100.0) / 365 *
            CASE 
                WHEN CAST(GETDATE() AS DATE) > DueDate 
                    THEN DATEDIFF(DAY, DueDate, CAST(GETDATE() AS DATE))
                ELSE 0
            END ) - TotalPaid ),
    CreatedDate datetime2 not null default SYSDateTime() --if we don't have any date, the system date could be considered.);


--------------------------------------------------------------------------------------
--Create Table Repayment
---------------------------------------------------------------------------------------


use ADB_Banking_Platform
  go
 create table Repayments(
 RepaymentID int identity(1,1) not null primary key,
 OverdueFeesID int NOT NULL foreign key references OverdueFees(OverdueFeesID),
 PaymentMethod nvarchar(50) check (PaymentMethod in ( 'Cash','BankTransfer','Card')) not null,
 Amount decimal (15,2) not null CHECK (Amount > 0),
 RepaymentDateandTime datetime2 not null DEFAULT SYSDATETIME());

 ---------------------------------------------------------------------------
 ---Insertting Important Triggers before Insertting data
 ---------------------------------------------------------------------------
 --trigger number 1: totalpaid should be updated from repayments table
 --this trigger inserted before populating tables to calculate totalpaid

USE ADB_Banking_Platform;
GO
CREATE TRIGGER TR_UpdateTotalPaid
ON Repayments
AFTER INSERT         --This could be done for update and delete as well, but now for this question I consider only update based on questions.
AS
BEGIN

    UPDATE o
    SET o.TotalPaid = o.TotalPaid + i.Amount    --total paid will be updated base on repayment amount and previous total paid.
    FROM OverdueFees AS o
    JOIN inserted AS i                
        ON o.OverdueFeesID = i.OverdueFeesID;
END;
GO
 

 ----------------------------------------------------------------------
 ---Inserting data in Customer
 ---------------------------------------------------------------------


 USE ADB_Banking_Platform;
GO
INSERT INTO Customers
(FirstName, LastName, DateOfBirth, UserName, Password, Email, MobilePhone, AddressLine1, AddressLine2, City, PostCode)
VALUES
('Ali',  'Ahmadi', '1995-05-10', 'Aliii',  HASHBYTES('SHA2_256','Ali1234*'),  'ali.ahmadi@gmail.com', '07123456781', '12 King Street',   NULL,  'Manchester', 'M11AA'),
 ('Sara', 'Mohammadi', '1998-02-20', 'Sarahm',       HASHBYTES('SHA2_256','Sara1111*'),   'sara.m@gmail.com',     '07123456782', '34 Queen Road',    'Flat 2',  'London',   'SW1AA'),
 ('Reza', 'Karimi',    '1992-07-15', 'Rezakarimii',  HASHBYTES('SHA2_256','Reza1377!'),   'reza.k@gmail.com',     '07123456783', '56 Park Lane',     NULL,      'Leeds',    'LS12BB'),
('Nima',  'Hosseini',  '1993-03-25', 'Nimahosseini', HASHBYTES('SHA2_256','Nima1405*'),   'nima.h@gmail.com',     '07123456784', '78 Hill Street',   NULL,      'Liverpool',  'TF27FA'),
 ('Mina', 'Akbari',    '1996-08-05', 'Minaakbari',  HASHBYTES('SHA2_256','Mina1380*'),  'mina.a@gmail.com',     '07123456785', '90 Green Road',    'Apt 4',   'Bristol',    'TF43GQ'),
('Omid', 'Rahimi',    '1991-11-11', 'Omidrahimi',  HASHBYTES('SHA2_256','Omid1379*'),   'omid.r@gmail.com',  '07123456786', '11 River View',    NULL,      'Sheffield',  'S15EE'),
 ('Lina', 'Zare','1999-09-09', 'Linazarem',    HASHBYTES('SHA2_256','Lina1381*'),   'lina.z@gmail.com',     '07123456787', '22 Market Street', NULL,      'Oxford',   'OX16FF'),
('Arman','Jafari',    '1994-01-12', 'Armanj',   HASHBYTES('SHA2_256','Arman122*'),   'arman.j@gmail.com',    '07123456788', '1 Oxford St',      NULL,      'London',     'W11AA'),
 ('Haniye','Rostami',   '1997-06-18', 'Haniyeh',      HASHBYTES('SHA2_256','Haniye144*'),  'haniye.r@gmail.com',   '07123456789', '22 Baker St',      NULL,      'London',  'W21BB'),
('Kian',  'Moradi',    '1990-03-10', 'Kianmoradi',   HASHBYTES('SHA2_256','Kian1277!'),   'kian.m@gmail.com',     '07123456790', '5 Elm St',       NULL,    'Leeds',   'LS33CC'),
('Parsa','Ghaffari',  '1993-09-22', 'ParsaG',    HASHBYTES('SHA2_256','Parsa1450!'),  'parsa.g@gmail.com',    '07123456791', '78 Lake Rd',       NULL,    'Manchester', 'M22DD'),
 ('Zahra', 'Nazari',    '1998-12-01', 'Zahran',       HASHBYTES('SHA2_256','Zahra1377*'),  'zahra.n@gmail.com',    '07123456792', '9 Hill Rd',     NULL,   'Bristol',  'BS11EE'),
('Mehdi', 'Salimi',    '1992-11-11', 'Mehdis',    HASHBYTES('SHA2_256','Mehdi1367*'),  'mehdi.s@gmail.com',    '07123456793', '14 River St',   NULL,      'Sheffield', 'S22FF'),
 ('Elnaz','Khosravi',  '1996-05-05', 'Elnazk',       HASHBYTES('SHA2_256','Elnaz1378!'),  'elnaz.k@gmail.com',    '07123456794', '88 Green St',     NULL,      'Oxford',  'OX22GG'),
('Sina',  'Abbasi',    '1991-07-07', 'Sinaa',    HASHBYTES('SHA2_256','Sina1380*'),   'sina.a@gmail.com',     '07123456795', '44 King Rd',       NULL,  'Liverpool',  'L11HH');
GO


-------------------------------------------------------------
-- Insert Accounts
--------------------------------------------------------------

 USE ADB_Banking_Platform;
GO
INSERT INTO Accounts
(CustomerID, AccountType, AccountName, AccountOpeningDate, Status, AccountCloseDate, AccountFreezeDate, ReferenceNumber)
VALUES
(1,  'Savings',   'Standard',    '2023-01-10', 'active',  NULL, NULL,      'SS00004'),
(2,  'Checking',  'Daily Current',    '2023-02-15', 'active',  NULL, NULL,   'CD00005'),
 (3,  'Loan',     'Car Loan Plan',    '2023-03-20', 'active',  NULL, NULL,     'LC00010'),
 (4,  'Credit Card', 'Gold Credit Card', '2023-04-05', 'active',  NULL, NULL,         'CG00023'),
 (5,  'Investment',  'Investment',       '2023-05-12', 'dormant', NULL, NULL,  'CG00005'),
(6,  'Loan',    'Home Loan Plan',   '2023-06-18', 'active',  NULL, NULL,    'LN100002'),
(7,  'Savings',   'Student Saver',    '2023-07-01', 'frozen',  NULL, '2024-01-15', 'SS00008'),
(8,  'Savings',     'Standard',     '2023-08-01', 'active',  NULL, NULL,         'SV200001'),
 (9,  'Checking',    'Current Plus',     '2023-08-05', 'active',  NULL, NULL,  'CH200001'),
(10, 'Loan',        'Personal Loan',    '2023-08-10', 'active',  NULL, NULL,    'LP200001'),
 (11, 'Credit Card', 'Silver Card',      '2023-08-15', 'active',  NULL, NULL,    'CC200001'),
(12, 'Investment',  'Stocks Plan',      '2023-08-20', 'dormant', NULL, NULL,    'IN200001'),
 (13, 'Loan',    'Education Loan',   '2023-08-25', 'active',  NULL, NULL,     'LN200002'),
 (14, 'Savings',     'Holiday Saver',    '2023-09-01', 'frozen',  NULL, '2024-02-01', 'SV200002'),
(15, 'Checking',    'Business Current', '2023-09-05', 'active',  NULL, NULL,         'CH200002');

GO

---------------------------------------------------------------------
--insert into Transaction
---------------------------------------------------------------

 USE ADB_Banking_Platform;
GO
INSERT INTO Transactions
(AccountID, TransactionAmount, TransactionType, TransactionStatus, TransactionDate, DueDate, CompletionDate)
VALUES
(1,  1500.00, 'Deposit',  'Completed', '2026-03-01 09:15:00', NULL,      '2026-03-01 09:15:00'),
(2,  200.00,  'Withdrawal', 'Completed', '2026-03-05 14:20:00', NULL,    '2026-03-05 14:20:00'),
 (3,  300.00,  'Payment',    'Completed', '2026-03-10 10:00:00', '2026-03-15', '2026-03-14 12:00:00'),
(3,  350.00,  'Payment',  'Pending',   '2026-04-01 11:00:00', '2026-04-10', NULL),
(4,  180.00,  'Payment',    'Pending',   '2026-04-13 13:00:00', '2026-04-27', NULL),
 (5,  2500.00, 'Deposit',  'Completed', '2026-03-18 09:00:00', NULL,         '2026-03-18 09:00:00'),
(6,  500.00,  'Payment',    'Pending',   '2026-04-14 10:00:00', '2026-04-28', NULL),
(8,  800.00,  'Deposit',  'Completed', '2026-03-10 09:00:00', NULL,     '2026-03-10 09:00:00'),
(9,  120.00,  'Withdrawal', 'Completed', '2026-03-11 14:30:00', NULL,   '2026-03-11 14:30:00'),
 (10, 400.00,  'Payment',    'Completed', '2026-03-12 10:15:00', '2026-03-18', '2026-03-17 11:00:00'),
(10, 450.00,  'Payment',  'Pending',   '2026-04-01 12:00:00', '2026-04-10', NULL),
 (11, 200.00,  'Payment',    'Pending',   '2026-04-14 08:45:00', '2026-04-27', NULL),
(11, 220.00,  'Payment',  'Pending',   '2026-04-02 09:20:00', '2026-04-12', NULL),
 (12, 3000.00, 'Deposit',  'Completed', '2026-03-20 13:00:00', NULL,         '2026-03-20 13:00:00'),
 (13, 600.00,  'Payment',    'Completed', '2026-03-22 15:10:00', '2026-03-28', '2026-03-27 10:30:00'),
(14, 275.00,  'Payment', 'Failed',    '2026-04-05 10:30:00', '2026-04-11', NULL);
GO

------------------------------------------------------------------------
--insert into OverDueFees
-------------------------------------------------------------------------

 USE ADB_Banking_Platform;
GO
INSERT INTO OverdueFees
(TransactionID, DueDate, OriginalAmount, AnnualInterestRate, CreatedDate)
VALUES
( 4,'2026-04-10', 350.00, 10.00,'2026-04-11 09:00:00'),
 (11,'2026-04-10', 450.00, 11.00, '2026-04-11 11:30:00'),
(13,'2026-04-12', 220.00, 12.50, '2026-04-13 14:15:00');
GO

-----------------------------------------------------------------------------
--Insert into Repayments
----------------------------------------------------------------------------

 USE ADB_Banking_Platform;
GO
INSERT INTO Repayments
(OverdueFeesID, PaymentMethod, Amount, RepaymentDateandTime)
VALUES
(1,'Card',   100.00, '2026-04-12 10:15:00'),
(2,'BankTransfer',450.00, '2026-04-13 14:20:00'),
(3,'Cash',   150.00, '2026-04-14 09:00:00');
GO


---------------------------------------------------------------------------------
---Test the trigger TR_UpdateTotalPaid   --I want to test the trigger which updates total paid
---------------------------------------------------------------------------------

 USE ADB_Banking_Platform;
GO
select OverdueFeesID, TotalPaid
from OverdueFees
where OverdueFeesID = 1;

 USE ADB_Banking_Platform;
GO
INSERT INTO Repayments --insertind data in repayments
(OverdueFeesID, PaymentMethod, Amount)
VALUES
(1, 'Card', 50);        --It must be updated in answer

 USE ADB_Banking_Platform;
GO
select OverdueFeesID, TotalPaid
from OverdueFees
where OverdueFeesID = 1;  


----------------------------------------------------------------------------
--Adding index in usefull columns for improving operations
----------------------------------------------------------------------------
--I read all questions and separates the column which will be used most  



use ADB_Banking_Platform
go
CREATE INDEX IndexForAccounts
ON Accounts(AccountName, AccountOpeningDate DESC);
GO

use ADB_Banking_Platform
go
CREATE INDEX IndexForTransactions
ON Transactions(DueDate, TransactionStatus, TransactionType);
GO

use ADB_Banking_Platform
go
CREATE INDEX IndexForOverDueFees
ON OverdueFees(TransactionID);
GO

use ADB_Banking_Platform
go
CREATE INDEX IndexForRepayments
ON Repayments(OverdueFeesID);
GO

--------------------------------------------------------------------------------------------------------
--Question.2-A     Search bank accounts or products by account/product name. Results must be sorted by
--most recently opened accounts first. This will allow them to query for a specific account.
--------------------------------------------------------------------------------------------------------
-- The question is a bit ambiguous regarding whether the search should be based on 
-- account name or customer name. Therefore, this answers are writen for both:
-- A) Searching by account name
-- B) Searching by customer (account holder) name


--SOLUTION A)Searching by Account name

use ADB_Banking_Platform
go
create procedure GrabAccounts --create procedure that take account name [like saver] and return the table of results
(@AccountName as nvarchar(50))   
as 
begin
select AccountOpeningDate,AccountType,Status,AccountName
 from dbo.Accounts
 where AccountName like '%'+@AccountName+'%'
 order by AccountOpeningDate desc   --sorted opening date in descending order to show most recent opening date
end

--A-Test
use ADB_Banking_Platform
go
exec GrabAccounts 'saver'


--SOLUTION B, by searchin customer name;

use ADB_Banking_Platform
go
create procedure GrabAccountsByCustomer   --this procedure take a customer name or last name and result the table of information
(@CustomerName nvarchar(50))
as 
begin
 select 
     a.AccountOpeningDate,a.AccountType,a.Status,a.AccountName,c.FirstName,c.LastName
 from dbo.Accounts as a
 inner join dbo.Customers as c 
     on a.CustomerID = c.CustomerID
 where 
     c.FirstName like '%'+@CustomerName+'%'   --both name or last name could be considered
     or c.LastName like '%'+@CustomerName+'%'
 order by a.AccountOpeningDate desc
end
------------- B TEST
use ADB_Banking_Platform
go
exec GrabAccountsByCustomer 'Ali'


------------------------------------------------------------------------------------------------------------
--Question 2-B: Return all loan or credit payments due in less than 5 days (i.e., the system date when the 
--query is run). It will show all pending payments are due soon. 
------------------------------------------------------------------------------------------------------------

--extracting pending payments due within the next 5 days 
-- for loan and credit card accounts with current date filtered

use ADB_Banking_Platform
go
create procedure ReturnPaymentsIn5 
as
begin
 select t.DueDate,t.transactionID,t.TransactionType,a.accountType,a.accountName,t.transactionStatus
 from Transactions t inner join Accounts a 
 on t.accountID = a.AccountID
 where  
  t.transactionType = 'payment'
 and t.transactionstatus = 'pending'
 and a.accountType in ('loan', 'credit card')
 and  t.Duedate >= cast (getdate() as date) and datediff (day,cast (getdate() as date),t.duedate)<5
end


--test question 2-2

exec ReturnPaymentsIn5;





---------------------------------------------------------------------------------------------------
--Question 2-C--Insert a new bank customer into the database 
-------------------------------------------------------------------------------------------------
-- using TRY...CATCH and try..end for error handling and I developed HASHBYTES for security.


-- Note*: As an extended solution to this question, an additional stored procedure
-- is developed in the 'Extra Work number 3' to insert 'customer' and 'account' data with a transaction 
--and ensuring data consistency.

-- For this question, the solution satisfies the question requirements.

use ADB_Banking_Platform
go
create procedure InsertIntoCustomersTable
(@FirstName nvarchar(30),
  @LastName nvarchar(60), @DateOfBirth date, @UserName nvarchar(20), @Password nvarchar(50),
  @Email nvarchar(50), @MobilePhone varchar(15),@AddressLine1 nvarchar(100),
  @AddressLine2 nvarchar(100),@City nvarchar (50),@PostCode nvarchar(15))
as
begin
 begin try
    insert into Customers(firstname,lastname,dateofbirth,username,password,email,mobilephone,addressline1,addressline2,city,postcode)
 values(@firstname,@lastname,@dateofbirth,@username,HASHBYTES('SHA2_256', @Password),@email,@mobilephone,@addressline1,@addressline2,@city,@postcode)
   print 'customer inserted successfully';   --using proper error
end try
begin catch
  print 'inserting customer failed'   ---using proper error
 print error_message();
 end catch
end;
go


--test question 2-C
use ADB_Banking_Platform
go
exec InsertIntoCustomersTable
    @firstname = 'aliaghar',
    @LastName = 'Test2',
    @DateOfBirth = '2001-01-02',
    @UserName = 'AliTestttr',
    @Password = 'Ali13772!',
    @Email = 'alitest2@gmail.com',
    @MobilePhone = '07951994533',
    @AddressLine1 = 'trinityy Address',
    @AddressLine2= 'southwater libraryy',
    @City = 'Manchester',
    @PostCode = 'tf27faa';

select *
from Customers

-------------------------------------------------------------------------------------------------------------------------------------------
-- 2-c-advanced: This is a extended solution for questin 2-C
-- Business idea: Insert customer and account within a transaction
-- This procedure inserts a new customer and their account together.
-------------------------------------------------------------------------------------------------------------------------------------------
-- creating procedure 
-- For the next, I want to write a stored procedure that inserting customer information and account details.
-- If any error occurs at any time and any stage, the transaction should be rolled back.

use ADB_Banking_Platform
go


CREATE PROCEDURE InsertNewCustomer_NewAccount
    @FirstName NVARCHAR(30), @LastName NVARCHAR(60),  @DateOfBirth DATE, @UserName NVARCHAR(20), @Password NVARCHAR(50),@Email NVARCHAR(50),
    @MobilePhone VARCHAR(15),  @AddressLine1 NVARCHAR(100), @AddressLine2 NVARCHAR(100), @City NVARCHAR(50), @PostCode NVARCHAR(15),  @AccountType NVARCHAR(20),
    @AccountName NVARCHAR(100), @AccountOpeningDate DATE, @Status NVARCHAR(20), @ReferenceNumber VARCHAR(20)
AS
BEGIN
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;    --to prevent reading uncommitted (fail) data
    BEGIN TRANSACTION;
    BEGIN TRY
        DECLARE @NewCustomerID INT;
        insert into customers
          (FirstName, LastName, DateOfBirth, UserName, Password,
           Email, MobilePhone, AddressLine1, AddressLine2, City, PostCode)
        VALUES
           (@FirstName, @LastName, @DateOfBirth, @UserName,
         HASHBYTES('SHA2_256', @Password),
         @Email, @MobilePhone, @AddressLine1, @AddressLine2, @City, @PostCode);
     SET @NewCustomerID = SCOPE_IDENTITY();  ---- Get the last inserted CustomerID in the current scope to link the new account to the correct customer
        insert into accounts
          (CustomerID, AccountType, AccountName, AccountOpeningDate, Status, ReferenceNumber)
          values
          (@NewCustomerID, @AccountType, @AccountName, @AccountOpeningDate, @Status, @ReferenceNumber);
        COMMIT TRANSACTION;
      END TRY
    begin catch
       ROLLBACK TRANSACTION;    --rolleback transaction if failed
     print 'Inserting information has been failed';
     PRINT error_message();
    end catch
END;
GO

--test extra work number 3
use ADB_Banking_Platform
go
select * 
from customers

use ADB_Banking_Platform
go
select * 
from accounts

--test for commit transaction
use ADB_Banking_Platform
go
EXEC InsertNewCustomer_NewAccount
 @FirstName = 'Testtt',@LastName =   'Customer2', @DateOfBirth = '2000-01-01',
 @UserName = 'Testuserr',
  @Password =  'Test12345!',@Email = 'user.customer@gmail.com',
  @MobilePhone =  '07115611111',   @AddressLine1 = 'iran Address', @AddressLine2 = NULL, @City =  'trafford',
  @PostCode = 'M1n2AA', @AccountType =  'Savings',
  @AccountName =  'Test Saver', @AccountOpeningDate = '2026-04-24',@Status = 'active',@ReferenceNumber = 'TEST601';

    select *
    from Customers

    --test for rolleback
    use ADB_Banking_Platform
   go
    EXEC InsertNewCustomer_NewAccount
  @FirstName = 'asghar', @LastName = 'abbasi',
  @DateOfBirth = '2000-01-01',@UserName = 'Rollbackt', @Password = 'password!',@Email = 'rollback@gmail.com',
   @MobilePhone = '07111789112',
  @AddressLine1 = 'Amol', @AddressLine2 = NULL,
  @City = 'mazandaran', @PostCode = 'M12AA',
 @AccountType = 'WrongType',  @AccountName = 'Bad Account',
  @AccountOpeningDate = '2026-04-24',@Status = 'active',  @ReferenceNumber = 'TEST002';


------------------------------------------------------------------------------------------------------
--question 2-D--Update the details for an existing customer. 
-----------------------------------------------------------------------------------------------------

-- This procedure assumes that the provided CustomerID exists and does not perform validation.

   use ADB_Banking_Platform
   go
   create procedure UpdateCustomerDetails
   (@customerid int,
   @FirstName nvarchar(30), @LastName nvarchar(60), @DateOfBirth date, @UserName nvarchar(20),  @Password nvarchar(50),
  @Email nvarchar(50),                --This procedure updates customer information using the provided CustomerId,
                                      -- with password hash and error handling using TRY...CATCH.
  @MobilePhone varchar(15), @AddressLine1 nvarchar(100), @AddressLine2 nvarchar(100), @City nvarchar (50),
  @PostCode nvarchar(15))
  as 
  begin 
  begin try
   update customers
   set firstname=@firstname,lastname=@lastname,dateofbirth=@dateofbirth,username=@username,
   password=HASHBYTES('SHA2_256', @Password)
   ,email=@email,mobilephone=@mobilephone,addressline1=@addressline1,addressline2=@addressline2,city=@city,postcode=@postcode
   where customerid=@customerid;
   print 'customer updated successfully';
  end try
  begin catch                               --like previous question, using catch for error handling
   print 'updating customer failed';
   print error_message();
  end catch
end;
go

-- In this questioin, @@ROWCOUNT can be used to verify whether the UPDATE affected any rows.


--question 2-D tested

use ADB_Banking_Platform
go
EXEC UpdateCustomerDetails
    @CustomerID = 13,
    @FirstName = 'Mehdi',
    @LastName = 'Salimi',
    @DateOfBirth = '1995-05-10',
    @UserName = 'aliaghaupdated',
    @Password = 'Ali1377!',
    @Email = 'aliupdated@gmail.com',
    @MobilePhone = '07123450600',
    @AddressLine1 = 'New Address',
    @AddressLine2 = 'Flat 5',
    @City = 'Manchester',
    @PostCode = 'M22BB';

use ADB_Banking_Platform
go
select *
from Customers

----------------------------------------------------------------------------------------------------------------------------
--Question3. The bank wants to be able to view all transactions including overdue fees or payments, showing all 
--past and current transactions with any associated overdue fees. 
--You should create a view containing all the required information.
-----------------------------------------------------------------------------------------------------------------------------

USE ADB_Banking_Platform;
GO

create view Alltransaction
AS
SELECT
    c.CustomerID,c.FirstName, c.LastName,
    a.AccountID, a.AccountName,a.AccountType, a.status, t.TransactionID, t.TransactionType, t.TransactionAmount, t.TransactionStatus,
    t.TransactionDate, t.DueDate, t.CompletionDate, o.OverdueFeesID,  o.OriginalAmount,  o.AnnualInterestRate, o.OverdueDays,  o.OverdueFeesAmount, o.TotalPaid,
    o.Balance, o.CreatedDate AS OverdueCreatedDate, r.RepaymentID,
    r.PaymentMethod,  r.Amount AS RepaymentAmount, r.RepaymentDateandTime
from Customers c
inner join Accounts a
    on c.CustomerID = a.CustomerID
inner join Transactions t
    on a.AccountID = t.AccountID
left join OverdueFees o             ---we should use left join to keep all data in table left to see past data
    on t.TransactionID = o.TransactionID
left join repayments r
    on o.OverdueFeesID = r.OverdueFeesID;
GO

--getting this view tested
use ADB_Banking_Platform
go
Select *
from Alltransaction;


----------------------------------------------------------------------------------------------------------------------------------
--- Question4. --Create a trigger that automatically updates the status of a Loan or Credit Card type account when 
--the final scheduled payment is recorded as completed. For example, the trigger could update the 
--account status from 'Active' to 'Closed' when the loan balance reaches zero. Clearly state the 
--business rules your trigger implements.  
--------------------------------------------------------------------------------------------------------------------------------

--preprocess Q4:

-- To solve this question, i added TotalOwed column to the Accounts table.
-- This column is used for Loan and Credit Card accounts to identify whether the final payment has been completed by comparing totalowed with the paymeents.
-- If the finall payments equall TotalOwed amount, the trigger can update the account status to 'closed'.
use ADB_Banking_Platform
go
ALTER TABLE dbo.Accounts  
ADD TotalOwed DECIMAL(15,2) NULL;  

UPDATE dbo.Accounts
SET TotalOwed = 650.00
WHERE AccountType IN ('Loan', 'Credit Card');

--------------------------------------------------------------------
--solve Q4:

--This trigger updates the account status to 'closed' when totalowed are completelly payed
-- also checks:
-- 1. The updated transaction is a completed payment
-- 2. The total completed payments meet TotalOwed amount
-- 3. no remaining pending payments
-- If all conditions are fullfilled, the account is label as closed and also the close date is recorded.

use ADB_Banking_Platform
go
create trigger UpdateAccountStatus
on transactions
after update 
as
begin
 update a
 set a.status = 'closed', a.AccountCloseDate = cast(getdate() as date)
 from accounts a inner join inserted i on a.AccountID = i.AccountID
 where a.accounttype in ('loan' ,'credit card')
 and a.status = 'active' and i.transactiontype = 'payment'
 and i.transactionstatus = 'completed'
 and a.totalOwed is not null
 and a.totalOwed <=
 ( select isnull(sum(t.transactionAmount),0)
  from transactions t
  where t.accountid=a.accountid
  and t.transactiontype= 'payment'
  and t.transactionstatus = 'completed')

 and not exists   --if at least 1 row that meet this codition, this trigger won't wotk.
 (
   select 1
   from transactions t
   where t.AccountID = a.AccountID and t.transactiontype = 'payment' and t.transactionstatus = 'pending'
 );
end

--test question 4 

use ADB_Banking_Platform
go
UPDATE dbo.Transactions
SET TransactionStatus = 'Completed',
    CompletionDate = SYSDATETIME()
WHERE TransactionID = 4;

use ADB_Banking_Platform
go
SELECT AccountID, AccountType, Status, AccountCloseDate, TotalOwed
FROM dbo.Accounts
WHERE AccountID = 3;
 
 -------------------------------------------------------------------------------------------------------------------------------
----Question number 5. -You should provide a function, view, or SELECT query with customers who paid less than 50% of 
--their overdue fees and list the count of that customer as well.
-------------------------------------------------------------------------------------------------------------------------------

-- I developed a view which extract the required customer, account, transaction, and overdue fee information.
-- The query uses this view to select customers whose TotalPaid is less than 50% of their total overdue balance, including original amount and calculated overdue fees.

use ADB_Banking_Platform
go
create view NecessaryInformation
as
select c.customerid,c.firstname,c.lastname,a.accountid,a.accountType,a.status,t.TransactionID,o.overduefeesid,o.overduefeesamount,o.totalpaid,o.duedate,o.OverdueDays, o.balance,
o.originalamount
from customers as c inner join accounts as a on c.customerid=a.customerid inner join transactions t on a.accountid=t.accountid 
inner join OverdueFees as o on t.transactionid = o.transactionid 

select *
from necessaryinformation

---solving stage 2 of question
use ADB_Banking_Platform
go
select customerid,firstname,lastname,count (*) as CountOfCustomer --CountOfCustomer shows how many overdue records meet this condition for each customer.
from NecessaryInformation
where TotalPaid<0.50*(OriginalAmount+OverdueFeesAmount)
group by CustomerId,FirstName,LastName



--------------------------------------------------------------------------------------------------------------
--Extra functions for higher mark
---------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------------------------------------------------------------
--Extra work number 1. Business Idea: Eploration for getting new loan eligibility (A view and function which check Customer repayment status by reference number)

-- I'm adding a function here that takes a reference number as input and returns the customer's information and whether they can get new loan or not.
------------------------------------------------------------------------------------------------------------------------------------------------------

-- This section creates a view to collect customer, account, transaction, and overdue fee details.
-- The function then takes a reference number to check whether the customer has unpaid overdue balances or not.
-- then returns a short eligibility message based on the customer's repayment status.
--it will show a message demonstrate that the customer has no pending payments and is eligible to apply for a loan.

--stage 1. create view
use ADB_Banking_Platform
go
create view vw_CustomerTransactionHistory
AS
SELECT 
    c.CustomerID, c.FirstName,c.LastName,a.AccountID,a.AccountName,a.AccountType,
a.ReferenceNumber,a.Status,t.TransactionID,t.TransactionType, t.TransactionStatus, t.TransactionDate,
  t.DueDate, t.CompletionDate,o.OverdueFeesID,o.OverdueDays,o.OriginalAmount,o.OverdueFeesAmount,
    o.TotalPaid, o.Balance
FROM Customers AS c
INNER JOIN Accounts AS a
    ON c.CustomerID = a.CustomerID
INNER JOIN Transactions AS t
    ON a.AccountID = t.AccountID
LEFT JOIN OverdueFees AS o             
    ON t.TransactionID = o.TransactionID;
GO

select*
from vw_CustomerTransactionHistory

--stage 2. extracting history of customer
use ADB_Banking_Platform
go
create function dbo.HistoryForCustomers
(@referencenumber nvarchar(50))
returns nvarchar (200)
as
begin
 declare  @totalamount  decimal(15,2),
          @totalpaid  decimal(15,2),
          @result nvarchar(200);

select @totalamount = ISNULL(SUM(ISNULL(OriginalAmount,0) + ISNULL(OverdueFeesAmount,0)),0),
 @totalpaid = ISNULL(SUM(ISNULL(TotalPaid,0)),0)
from vw_CustomerTransactionHistory
where referencenumber = @referencenumber
if (@totalamount = 0)
  set @result =  'this customer has no installment to pay and eligible for getting loan'  -- this customer eligible for getting new loan
else if (@totalamount<=@totalpaid)
 set @result = 'This customer has paid all instalments and may be eligible for a loan' --this customer eligible for getting new loan
else  
 set @result= 'This customer has unpaid instalments or overdue fees to pay';   --this customer is not eligible
return @result;
end;


---test Extra work number 1 
use ADB_Banking_Platform
go
SELECT dbo.HistoryForCustomers('CC200001');



----------------------------------------------------------------------------------------------------------------------------------------
--extra work number 2. Bussines Idea: Identify low-engagement long-term customers
--definition: identify customer who have account in our bank for more than 3 years and haven't had suffincient transactions and engagement. 
----------------------------------------------------------------------------------------------------------------------------------------

--This query finds customers who have held an account for more than 3 years
-- but have low transaction activity. These customers could be targeted
-- for engagement campaigns such as SMS or promotional offers.

use ADB_Banking_Platform
go

select
c.customerid,c.firstname,c.lastname,c.mobilephone,a.accountid,a.accounttype,
a.accountopeningdate,count(t.transactionid) as Transactioncount, ISNULL(sum(t.transactionamount),0) as totaltransactionamount
from customers as c inner join accounts as a on c.customerid=a.CustomerID
left join transactions as t on t.AccountID=a.AccountID
WHERE DATEDIFF(DAY, a.AccountOpeningDate, CAST(GETDATE() AS DATE)) > 1000  --differences from account openning date and now, which is more than 1000 days or approximately 3 years
group by c.customerid,c.firstname,c.lastname,c.mobilephone,a.accountid,a.AccountType,a.AccountOpeningDate
having count (t.transactionid)<2 and ISNULL(SUM(t.TransactionAmount), 0) < 500  --have less than 2 transaction and less than 500 pound amount 





  
---------------------------------------------------------------------------------------------------------------
---extra work number 4. Business idea - Identify top customers by completed transaction amount
------------------------------------------------------------------------------------------------------------------


--This query ranks customers based on the total value of their completed transactions.

  use ADB_Banking_Platform
   go

select *
from 
   (select  c.customerid,c.firstname,c.lastname,sum (t.transactionamount) as totalamount,
           row_number() over (ORDER BY SUM(TransactionAmount) DESC) AS Rank      --a ranking to customers based on total transaction amount
 from customers as c inner join accounts as a on c.customerid = a.customerid inner join transactions as t on a.accountid = t.accountid
 WHERE t.TransactionStatus = 'Completed'
group by c.customerid,c.firstname,c.lastname) t1
 where rank <=5;  --identify rank 1 to 5




 ------------------------------------------------------------------------------------------------------------
 --Concurrency code
 ------------------------------------------------------------------------------------------------------------
 -- This script demonstrates handling concurrent updates on account balances
 -- using transaction isolation and row  locking to prevent inconsistent updates.

 USE ADB_Banking_Platform;
GO


SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- Demonstration of safe balance update under concurrent access

BEGIN TRANSACTION;

DECLARE @CurrentBalance DECIMAL(15,2); 

SELECT @CurrentBalance = TotalOwed
FROM dbo.Accounts WITH (UPDLOCK) ---- Applies an update lock on the selected row to prevent other transactions from modifying it
WHERE AccountID = 3;

IF @CurrentBalance >= 100.00
BEGIN
    UPDATE dbo.Accounts
    SET TotalOwed = TotalOwed - 100.00
    WHERE AccountID = 3;

    PRINT 'Transaction successful. balance updated: '    -- how to safely update TotalOwed under concurrent access
          + CAST((@CurrentBalance - 100.00) AS NVARCHAR);
END
ELSE
BEGIN
    PRINT 'Not enough balance.';
END;

ROLLBACK TRANSACTION;  -- rollback for testing purposes only
GO



 ----------------------------------------------------------------------------------------------------------------------------
 ----- Database security
-----------------------------------------------------------------------------------------------------------------------------
-- This section defines roles with different levels:
-- 1. BankAdmin: Full access to all tables (SELECT, INSERT, UPDATE, DELETE)
-- 2. BankEmployee: Limited access for inserting and viewing customer and account data
-- 3. BankOperator: Read access to customer/account/transaction data with restricted update rights to answering customers question


-- Users are then created and assigned to roles to enforce access control.

USE ADB_Banking_Platform;
GO
CREATE ROLE BankAdmin;
CREATE ROLE BankEmployee;
CREATE ROLE BankOperator;
GO
--1.BankAdmin (full access) --admin has been given full access to justify database
USE ADB_Banking_Platform;
GO
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Customers TO BankAdmin;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Accounts TO BankAdmin;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Transactions TO BankAdmin;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.OverdueFees TO BankAdmin;
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Repayments TO BankAdmin;
GO
-- 2. BankEmployee 
USE ADB_Banking_Platform;
GO
GRANT SELECT, INSERT ON dbo.Customers TO BankEmployee;
GRANT SELECT, INSERT ON dbo.Accounts TO BankEmployee;
GO
-- 3. BankOperator --They should have access to see the information of customers to give customers information
USE ADB_Banking_Platform;
GO
GRANT SELECT ON dbo.Customers TO BankOperator;
GRANT SELECT ON dbo.Accounts TO BankOperator;
GRANT SELECT ON dbo.Transactions TO BankOperator;
-- Letting bank operator to justify account after taking customer informarion
USE ADB_Banking_Platform;
GO
GRANT UPDATE ON dbo.Customers TO BankOperator;
GO
------
DENY DELETE ON dbo.Customers TO BankOperator;  --restricted using DENY where necessary.

-- Create Users 
USE ADB_Banking_Platform;
GO
CREATE USER AdminUser WITHOUT LOGIN;
CREATE USER EmployeeUser WITHOUT LOGIN;
CREATE USER OperatorUser WITHOUT LOGIN;
GO

-- Assign Users to Roles
USE ADB_Banking_Platform;
GO
ALTER ROLE BankAdmin ADD MEMBER adminUser;
ALTER ROLE BankEmployee ADD MEMBER EmployeeUser;
ALTER ROLE BankOperator ADD MEMBER OperatorUser;
GO

-----