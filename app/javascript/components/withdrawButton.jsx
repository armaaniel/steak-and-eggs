import React, { useState } from 'react'

const Button = () => {
	
	const [isOpen, setIsOpen] = useState(false);
	
	const openDialog = () => setIsOpen(true);
	const closeDialog = () => setIsOpen(false);
	
	return (
		
		<div> 
			<button onClick={openDialog}>
				Withdraw Funds
			</button>
				
		{isOpen && (
			
			<div>
				<div className='background-overlay'></div>
				<div className='modal-dialog'>
					<form className = 'modal-contents' method='post' action='/balance'>
	   	 				<input type="hidden" name="authenticity_token" 
						value={document.querySelector("meta[name='csrf-token']")?.getAttribute("content")}/>
						<h2>Withdraw Funds</h2>
						<div>
							<input type='number' placeholder='Amount' name='amount'/>
						</div>
						<div>
							<input type='submit' name='commit' value='withdraw funds'/>
						</div>
					</form>
					<button className='close-button' onClick={closeDialog}>
						X
					</button>
				</div>
				</div>
		)}
			</div>
	);
};

export default withdrawButton;
