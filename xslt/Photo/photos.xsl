<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<photos>
			<xsl:for-each select="games/game">
				<xsl:if test="id = $game">
					<xsl:for-each select="teams/team">
						<xsl:if test="id = $team">
							<xsl:for-each select="photos/photo">
								<photo>
									<guid><xsl:value-of select="guid"/></guid>
									<judge><xsl:value-of select="judge"/></judge>
									<notes><xsl:value-of select="notes"/></notes>
									<mime><xsl:value-of select="mime"/></mime>
									<exposure><xsl:value-of select="exposure"/></exposure>
									<submission><xsl:value-of select="submission"/></submission>
								</photo>
							</xsl:for-each>
						</xsl:if>
					</xsl:for-each>
				</xsl:if>
			</xsl:for-each>
		</photos>
	</xsl:template>
</xsl:stylesheet>
