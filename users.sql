CREATE TABLE [dbo].[Users](
	[id] [char(28)] NOT NULL,
	[name] [nvarchar](32) NOT NULL,
	[email] [varchar](128) NOT NULL,
	[created] [datetimeoffset](2) NOT NULL,
	[lastLogin] [datetimeoffset](2) NOT NULL,
 CONSTRAINT [PK_Users] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO
