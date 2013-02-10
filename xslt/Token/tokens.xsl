<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<xsl:for-each select="games/game">
			<xsl:if test="id = $game">
				<xsl:for-each select="teams/team">
					<xsl:if test="id = $team">
						<tokens>
							<xsl:for-each select="tokens/token">
								<token>
									<token><xsl:value-of select="token"/></token>
								</token>
							</xsl:for-each>
						</tokens>
					</xsl:if>
				</xsl:for-each>
			</xsl:if>
		</xsl:for-each>
	</xsl:template>
</xsl:stylesheet>
