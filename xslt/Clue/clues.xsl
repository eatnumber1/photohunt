<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<clues>
			<xsl:for-each select="games/game">
				<xsl:if test="id = $game">
					<xsl:for-each select="clues/clue">
						<clue>
							<id><xsl:value-of select="id"/></id>
							<description><xsl:value-of select="description"/></description>
							<points><xsl:value-of select="points"/></points>
						</clue>
					</xsl:for-each>
				</xsl:if>
			</xsl:for-each>
		</clues>
	</xsl:template>
</xsl:stylesheet>
