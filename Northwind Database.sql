-- Microsoft SQL Server (Northwind Database)

-- Query 1: 
-- Total quantity by category (excluding names starting with B)
-- where category average quantity > overall average quantity

select c.CategoryName, 
      sum(Quantity) sumQ
from Categories c join Products p 
     on c.CategoryID = p.CategoryID 
	 join [Order Details] od on od.ProductID = p.ProductID
where c.CategoryName not like 'B%'
group by c.CategoryID , c.CategoryName
having AVG(Quantity) > (select AVG(Quantity)
                         from [Order Details])


-- Query 2: 
-- Country summary: inactive customers (no orders) and inactivity rate

select Country,
	   count(distinct c.CustomerID) TotalCustomers,
	   count(case when o.CustomerID is null then c.CustomerID end) InactiveCustomers,
	   cast(100.0 * count(case when o.CustomerID is null then c.CustomerID end)  /  count(distinct c.CustomerID) as decimal(5,2) ) InactiveCustomersPct
from Customers c left join Orders o
     on c.CustomerID = o.CustomerID
group by  Country
order by Country



-- Query 3: 
-- User-defined function to calculate final order price after discount

create function dbo.FinalPrice(@unitPrice money , @quantity smallint , @discount real)returns moneyas beginreturn(@unitPrice * @quantity *(1- @discount))endselect OrderID, ProductID, dbo.FinalPrice(UnitPrice,Quantity,Discount) FinalPricefrom [Order Details]order by OrderID

-- Query 4:
-- Window function: For each order, show first and last customer order dates, and days between

select *, 
      DATEDIFF(DAY, FirstOrder , LastOrder)  DaysBetweenOrders
from (

			select CustomerID, 
			       OrderID,
				   OrderDate,
				   FIRST_VALUE(OrderDate) over(partition by CustomerID
											   order by OrderDate ) FirstOrder,
				   LAST_VALUE(OrderDate) over(partition by CustomerID
											   order by OrderDate
											   rows between unbounded preceding and unbounded following) LastOrder
			from Orders

) Q_Orders

-- Query 5:
-- CTE + window: Top customer per category by total revenue

with CustomerCategoryRevenue 
as
(
   select CustomerID, 
          CategoryID, 
		  sum(Quantity * od.UnitPrice * (1 - Discount)) TotalRevenue,
		  DENSE_RANK() over(partition by CategoryID
						    order by sum(Quantity * od.UnitPrice * (1 - Discount)) desc) CustomerRank
		from Products p join [Order Details] od
			 on p.ProductID = od.ProductID 
			 join Orders o
			 on od.OrderID = o.OrderID
		group by CustomerID , CategoryID

)
select *
from CustomerCategoryRevenue
where CustomerRank = 1
order by CategoryID , TotalRevenue desc


-- Query 6:
-- CTE + window: Top 5 products by revenue & revenue share

with ProductsSales
as (
select p.ProductID, 
       ProductName,
	   coalesce(sum(Quantity),0) TotalQuantity,
	   count(distinct CustomerID) CustomerCount,
	   coalesce(sum(Quantity * od.UnitPrice * (1 - Discount)),0) TotalSales,
	   ROW_NUMBER() over (order by sum(Quantity * od.UnitPrice * (1 - Discount)) desc ) rowNum
from Products p left join [Order Details] od
     on p.ProductID = od.ProductID
	 left join Orders o
	 on od.OrderID = o.OrderID
group by p.ProductID , ProductName )

select ProductID, 
       ProductName, 
	   TotalQuantity,
	   CustomerCount,
	   TotalSales,
      round((TotalSales / (select SUM(Quantity * UnitPrice * (1 - Discount))
	                       from [Order Details]))*100,2) RevenueSharePercent
from ProductsSales
where TotalQuantity > 0 and rowNum <= 5
order by TotalSales desc


-- Query 7:
-- Pivot: total sales for each employee in each quarter of every year

select FullName,
       OrderYear,
       ISNULL([1],0) Q1,
	   ISNULL([2],0) Q2,
	   ISNULL([3],0) Q3,
	   ISNULL([4], 0) Q4
from 
(
		select e.EmployeeID,
		       FirstName + ' ' + LastName FullName , 
			   YEAR(OrderDate) OrderYear,
			   DATEPART(QUARTER , OrderDate) OrderQuarter,
			   (Quantity * UnitPrice * (1 - Discount)) TotalSales
		from Employees e join Orders o
			 on e.EmployeeID = o.EmployeeID
			 join [Order Details] od
			 on o.OrderID = od.OrderID ) Q
pivot(sum(TotalSales) for OrderQuarter in ([1],[2],[3],[4])) pivottable
order by FullName, OrderYear


-- Query 8:
-- Stored procedure: Employee order summary with revenue ranking and employee existence check

create or alter proc GetEmployeeOrderSummary @employeeID int
as
if not exists ( 
	select *
	from Employees
	where EmployeeID = @employeeID
	)
begin
        throw 50001, 'Employee not found', 1;
end;

select o.OrderID,
       orderDate,
	   CompanyName as customerName, 
       count(distinct ProductID) countProducts,
	   sum(Quantity * UnitPrice * (1 - Discount)) TotalRevenue,
	   DENSE_RANK() over(order by sum (Quantity*UnitPrice * (1 - Discount)) desc) SalesRank
from Customers c join Orders o
     on c.CustomerID = o.CustomerID
	 join [Order Details] od 
	 on o.OrderID = od.OrderID
where EmployeeID = @employeeID
group by o.OrderID , OrderDate , CompanyName

exec GetEmployeeOrderSummary 2
