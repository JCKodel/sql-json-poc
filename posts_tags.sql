CREATE TABLE [dbo].[Posts_Tags](
	[postId] [int] NOT NULL,
	[tag] [varchar](16) NOT NULL,
 CONSTRAINT [PK_Posts_Tags] PRIMARY KEY CLUSTERED 
(
	[postId] ASC,
	[tag] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[Posts_Tags]  WITH CHECK ADD  CONSTRAINT [FK_Posts_Tags_Posts] FOREIGN KEY([postId])
REFERENCES [dbo].[Posts] ([id])
ON DELETE CASCADE
GO

ALTER TABLE [dbo].[Posts_Tags] CHECK CONSTRAINT [FK_Posts_Tags_Posts]
GO
