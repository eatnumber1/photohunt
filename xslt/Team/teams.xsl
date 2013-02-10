<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<teams>
			<xsl:for-each select="games/game">
				<xsl:if test="id = $game">
					<xsl:for-each select="teams/team">
						<team>
							<id><xsl:value-of select="id"/></id>
							<name><xsl:value-of select="name"/></name>
						</team>
					</xsl:for-each>
				</xsl:if>
			</xsl:for-each>
		</teams>
	</xsl:template>
</xsl:stylesheet>
