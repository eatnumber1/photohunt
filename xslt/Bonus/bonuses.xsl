<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<xsl:for-each select="games/game">
			<xsl:if test="id = $game">
				<xsl:for-each select="clues/clue">
					<xsl:if test="id = $clue">
						<bonuses>
							<xsl:for-each select="bonuses/bonus">
								<bonus>
									<id><xsl:value-of select="id"/></id>
									<description><xsl:value-of select="description"/></description>
									<points><xsl:value-of select="points"/></points>
								</bonus>
							</xsl:for-each>
						</bonuses>
					</xsl:if>
				</xsl:for-each>
			</xsl:if>
		</xsl:for-each>
	</xsl:template>
</xsl:stylesheet>
