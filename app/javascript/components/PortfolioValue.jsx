import React, { useState, useEffect } from 'react';


const PortfolioValue = () => {
	
	const [value, setValue] = useState(0);
	
	useEffect(() => {
		async function getValue() {
			try {
				const response = await fetch('/aum')
				const data = await response.json()
				setValue(data)
			} catch (err) {
				console.log(err)
			}	
		}
		getValue();
		
		const interval = setInterval(getValue, 10000)
		
		return () => clearInterval(interval);
	
	}, []);
	
	return (
	
	<h2>{value}</h2>
	
	)

}

export default PortfolioValue